/**
 * Ensemble Server — Standalone HTTP server
 * Lightweight replacement for Next.js API routes.
 */

import http from 'http'
import fs from 'fs'
import os from 'os'
// Alias, want de request-handler gebruikt de naam `path` al voor de URL-pathname.
import nodePath from 'path'
import { fileURLToPath } from 'url'
const serverDir = nodePath.dirname(fileURLToPath(import.meta.url))
import { deleteTeam, loadTeams, getTeam, updateTeam, appendMessage, getMessages } from './lib/ensemble-registry'
import {
  createEnsembleTeam, getEnsembleTeam, listEnsembleTeams,
  getTeamFeed, sendTeamMessage, disbandTeam, reactivateTeam,
} from './services/ensemble-service'
import { getRuntime } from './lib/agent-runtime'
import { v4 as uuidv4 } from 'uuid'

const PORT = parseInt(process.env.ENSEMBLE_PORT || process.env.ORCHESTRA_PORT || '23000', 10)
const HOST = process.env.ENSEMBLE_HOST || '0.0.0.0'
const RATE_LIMIT_WINDOW_MS = 60_000
const RATE_LIMIT_MAX_REQUESTS = 100
const DEFAULT_CORS_ORIGIN_PATTERNS = [
  /^http:\/\/localhost(?::\d+)?$/i,
  /^http:\/\/127\.0\.0\.1(?::\d+)?$/i,
  /^http:\/\/\[::1\](?::\d+)?$/i,
]

type RateLimitEntry = {
  count: number
  windowStart: number
}

const rateLimitByIp = new Map<string, RateLimitEntry>()

// Periodic cleanup of stale rate limit entries to prevent unbounded Map growth
setInterval(() => {
  const now = Date.now()
  for (const [ip, entry] of rateLimitByIp) {
    if (now - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
      rateLimitByIp.delete(ip)
    }
  }
}, 60_000)

function getAllowedCorsOrigins(): string[] {
  const configured = process.env.ENSEMBLE_CORS_ORIGIN?.trim()
  if (!configured) return []

  return configured
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean)
}

function isAllowedOrigin(origin: string): boolean {
  const configuredOrigins = getAllowedCorsOrigins()
  if (configuredOrigins.length > 0) return configuredOrigins.includes(origin)
  return DEFAULT_CORS_ORIGIN_PATTERNS.some(pattern => pattern.test(origin))
}

function buildCorsHeaders(origin?: string): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Vary': 'Origin',
  }

  if (origin && isAllowedOrigin(origin)) {
    headers['Access-Control-Allow-Origin'] = origin
  }

  return headers
}

function json(res: http.ServerResponse, data: unknown, status = 200, origin?: string) {
  res.writeHead(status, buildCorsHeaders(origin))
  res.end(JSON.stringify(data))
}

async function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = ''
    req.on('data', chunk => body += chunk)
    req.on('end', () => resolve(body))
    req.on('error', reject)
  })
}

function getClientIp(req: http.IncomingMessage): string {
  const forwardedFor = req.headers['x-forwarded-for']
  if (typeof forwardedFor === 'string') {
    const firstIp = forwardedFor.split(',')[0]?.trim()
    if (firstIp) return firstIp
  }

  return req.socket.remoteAddress || 'unknown'
}

function isRateLimited(ip: string): boolean {
  const now = Date.now()
  const current = rateLimitByIp.get(ip)

  if (!current || now - current.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateLimitByIp.set(ip, { count: 1, windowStart: now })
    return false
  }

  current.count += 1
  return current.count > RATE_LIMIT_MAX_REQUESTS
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://localhost:${PORT}`)
  const path = url.pathname
  const method = req.method || 'GET'
  const origin = req.headers.origin

  if (origin && !isAllowedOrigin(origin)) {
    return json(res, { error: 'CORS origin forbidden' }, 403, origin)
  }

  // CORS preflight
  if (method === 'OPTIONS') {
    res.writeHead(204, buildCorsHeaders(origin))
    res.end()
    return
  }

  try {
    // Health check — always exempt from rate limiting
    if (path === '/api/v1/health') {
      // De preflight herstartte de service ooit puur op leeftijd, als proxy voor
      // "is hij met credentials gestart". ANTHROPIC_API_KEY en
      // CLAUDE_CODE_OAUTH_TOKEN staan echter niet eens in de env van de gezonde,
      // door launchd beheerde service (geverifieerd met `launchctl print`: enkel
      // PATH, HOME, XPC_SERVICE_NAME), dus die vars zeggen hier niets. claude en
      // codex bewaren hun login-status wel op schijf onder $HOME, dat de
      // launchd-plist wel correct doorgeeft. Bestandsaanwezigheid bewijst geen
      // geldig token (zelfde denkfout als de codex-probe uit #88 zou zijn), maar
      // is een eerlijker signaal dan een env var die de gezonde instantie nooit
      // heeft.
      const home = os.homedir()
      const hasClaudeCreds = fs.existsSync(nodePath.join(home, '.claude', '.credentials.json'))
      const hasCodexCreds = fs.existsSync(nodePath.join(home, '.codex', 'auth.json'))
      // Het veld heet naar wat het meet en niet naar wat je zou willen weten:
      // of de service bij de opslag kan, niet of het token daarin nog geldig is.
      // Die laatste vraag beantwoorden de live probes in de preflight.
      const credentialStore = (hasClaudeCreds || hasCodexCreds) ? 'readable' : 'unreachable'
      return json(res, {
        status: 'healthy',
        version: '1.0.0',
        credentialStore,
        uptimeSeconds: Math.round(process.uptime()),
      }, 200, origin)
    }

    // Hier stond een uitzondering op '/api/ensemble/', wat elke route is die deze
    // server heeft: de limiet van 100/min stond daarmee volledig uit. Alleen GET
    // op een los team en zijn feed blijven vrij, want dat zijn de routes die
    // pollers echt raken: cli/monitor.ts poll elke 2s allebei (per open monitor),
    // collab-poller.sh pingt het team-detail-endpoint eens per minuut, en
    // team-read.sh raakt de feed op het tempo van de agent. De lijst-route
    // (GET /api/ensemble/teams) en alle mutaties blijven gewoon gelimiteerd.
    const isTeamPoll = method === 'GET' && /^\/api\/ensemble\/teams\/[^/]+(?:\/feed|\/agents-status)?$/.test(path)
    if (!isTeamPoll && isRateLimited(getClientIp(req))) {
      return json(res, { error: 'Rate limit exceeded' }, 429, origin)
    }

    // List teams / Create team
    if (path === '/api/ensemble/teams') {
      if (method === 'GET') {
        const result = await listEnsembleTeams()
        return json(res, result.data, result.status, origin)
      }
      if (method === 'POST') {
        let body: unknown
        try {
          body = JSON.parse(await readBody(req))
        } catch {
          return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
        }
        const result = await createEnsembleTeam(body as Parameters<typeof createEnsembleTeam>[0])
        if (result.error) return json(res, { error: result.error }, result.status, origin)
        return json(res, result.data, result.status, origin)
      }
    }

    // Team operations: /api/ensemble/teams/:id
    const teamMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)$/)
    if (teamMatch) {
      const teamId = teamMatch[1]
      if (method === 'GET') {
        const result = getEnsembleTeam(teamId)
        if (result.error) return json(res, { error: result.error }, result.status, origin)
        return json(res, result.data, result.status, origin)
      }
      if (method === 'POST') {
        let body: Record<string, unknown>
        try {
          body = JSON.parse(await readBody(req))
        } catch {
          return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
        }
        const result = await sendTeamMessage(teamId, (body.to as string) || 'team', body.content as string, body.from as string, body.id as string, body.timestamp as string)
        if (result.error) return json(res, { error: result.error }, result.status, origin)
        return json(res, result.data, result.status, origin)
      }
      if (method === 'DELETE') {
        const result = await disbandTeam(teamId)
        if (result.error) return json(res, { error: result.error }, result.status, origin)
        return json(res, result.data, result.status, origin)
      }
    }

    // Agent Live Status: GET /api/ensemble/teams/:id/agents-status
    const agentStatusMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/agents-status$/)
    if (agentStatusMatch && method === 'GET') {
      const teamId = agentStatusMatch[1]
      const team = getTeam(teamId)
      if (!team) return json(res, { error: 'Team not found' }, 404, origin)

      const runtime = getRuntime()
      const messages = getMessages(teamId)
      const agents = team.agents || []

      const modelMap: Record<string, string> = {
        'agy': 'Orchestrator (Argon)',
        'agy-worker': 'Gemini 3.8 Flash (Medium)',
        'agy-pro': 'Claude Sonnet (Pro)',
        'ollama-gemma': 'Ollama Gemma 4 (12B Local)',
        'ollama-qwen': 'Ollama Qwen 3 Coder (30B Local)',
        'ollama/gemma4:12b': 'Ollama Gemma 4 (12B Local)',
        'ollama/qwen3-coder:30b': 'Ollama Qwen 3 Coder (30B Local)',
        'gemini-pro-orchestrator-g1-pro': 'Orchestrator (Argon)',
        'gemini-pro-orchestrator-neon': 'Orchestrator (Neon)',
        'gemini-3.8-flash-medium': 'Gemini 3.8 Flash (Medium)',
        'gemini-3.8-flash-high': 'Gemini 3.8 Flash (High)',
        'gemini-3.8-flash-low': 'Gemini 3.8 Flash (Low)',
        'cc-sonnet-medium': 'Claude Sonnet (Pro)',
        'cc-sonnet-high': 'Claude Sonnet (Pro) (High)',
        'cc-opus-medium': 'Claude Opus (Pro)',
        'gemini-4-argon-high': 'Gemini 4 Argon (High)',
        'gemini-4-argon-medium': 'Gemini 4 Argon (Medium)',
        'gemini-4-argon-low': 'Gemini 4 Argon (Low)',
        'gemini-4-neon-high': 'Gemini 4 Neon (High)',
        'gemini-4-neon-medium': 'Gemini 4 Neon (Medium)',
        'gemini-4-neon-low': 'Gemini 4 Neon (Low)',
      }

      const results = await Promise.all(agents.map(async (agent) => {
        const sessionName = `${team.name}-${agent.name}`
        let exists = false
        try {
          exists = await runtime.sessionExists(sessionName)
        } catch {}

        let paneContent = ''
        if (exists && typeof (runtime as any).capturePane === 'function') {
          try {
            paneContent = await (runtime as any).capturePane(sessionName, 60)
          } catch {}
        }

        let state: 'running' | 'thinking' | 'idle' | 'quota_exceeded' | 'offline' = 'idle'
        let detail = ''
        let thinkingTime = ''

        if (!exists) {
          state = 'offline'
          detail = 'Chưa bật / Ngoại tuyến'
        } else if (paneContent.includes('Individual quota reached') || paneContent.includes('quota reached')) {
          state = 'quota_exceeded'
          detail = '⚠️ Chạm trần Quota'
        } else {
          const thoughtMatch = paneContent.match(/Thought for ([0-9m s]+)/i)
          if (thoughtMatch) {
            thinkingTime = thoughtMatch[1].trim()
          }

          const actionsMatch = paneContent.match(/([0-9]+\s+more\s+actions[^\n\r]*|\d+\s+actions[^\n\r]*)/i)
          const actionsStr = actionsMatch ? ` • ${actionsMatch[1].replace(/[…\(\)]/g, '').trim()}` : ''

          const isBusy = paneContent.includes('esc to cancel') || /[⣾⣽⣻⢿⡿⣟⣯⣷]/.test(paneContent) || paneContent.includes('Running command') || paneContent.includes('Running (')

          if (isBusy) {
            if (paneContent.includes('Running command') || paneContent.includes('Running (') || paneContent.includes('Edited 1 file') || paneContent.includes('Edited ')) {
              state = 'running'
              detail = `⚡ Đang chạy lệnh & sửa code${actionsStr}${thinkingTime ? ` [Đã suy luận ${thinkingTime}]` : ''}`
            } else if (paneContent.includes('Explored ') || paneContent.includes('Explored 1 file')) {
              state = 'running'
              detail = `📁 Đang duyệt & đọc code${actionsStr}${thinkingTime ? ` [Đã suy luận ${thinkingTime}]` : ''}`
            } else {
              state = 'thinking'
              detail = `🧠 Đang suy luận chuyên sâu (${thinkingTime || 'Thinking...'})`
            }
          } else if (paneContent.includes('Press up to edit queued messages') || paneContent.trim().endsWith('>') || paneContent.includes('? for shortcuts')) {
            state = 'idle'
            detail = '💤 Đang trực tuyến (chờ việc)'
          } else {
            state = 'idle'
            detail = '🟢 Đang trực tuyến'
          }
        }

        const lastMsg = [...messages].reverse().find(m => m.from === agent.name)
        const modelDisplay = modelMap[agent.program] || agent.program || 'Auto'

        // Trích xuất các dòng tiến trình thực tế (Thought for, Ran, Explored, Edited, Running)
        let meaningfulTail = ''
        if (paneContent) {
          const lines = paneContent.split('\n')
          const progressLines = lines.filter(l => 
            l.includes('Thought for') || 
            l.includes('Ran ') || 
            l.includes('Explored ') || 
            l.includes('Edited ') || 
            l.includes('Running ') ||
            l.includes('actions') ||
            l.includes('esc to cancel')
          )
          if (progressLines.length >= 2) {
            meaningfulTail = progressLines.slice(-7).join('\n')
          } else {
            meaningfulTail = lines.slice(-8).join('\n')
          }
        }

        return {
          agentId: agent.agentId,
          name: agent.name,
          role: agent.role,
          program: agent.program,
          instruction: agent.instruction || '',
          modelDisplay,
          status: agent.status,
          alive: exists,
          state,
          detail,
          thinkingTime,
          lastMessageSnippet: lastMsg ? (lastMsg.content.length > 80 ? lastMsg.content.slice(0, 80) + '...' : lastMsg.content) : null,
          lastMessageAt: lastMsg?.timestamp || null,
          paneTail: meaningfulTail,
        }
      }))

      return json(res, {
        teamId: team.id,
        teamStatus: team.status,
        agents: results,
        timestamp: new Date().toISOString()
      }, 200, origin)
    }

    // Reactivate: /api/ensemble/teams/:id/reactivate
    const reactivateMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/reactivate$/)
    if (reactivateMatch && method === 'POST') {
      const result = await reactivateTeam(reactivateMatch[1])
      if (result.error) return json(res, { error: result.error }, result.status, origin)
      return json(res, result.data, result.status, origin)
    }

    // Launch new team / session: POST /api/ensemble/launch
    if (path === '/api/ensemble/launch' && method === 'POST') {
      let body: Record<string, unknown>
      try {
        body = JSON.parse(await readBody(req))
      } catch {
        return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
      }
      const task = ((body.task || body.description || '') as string).trim()
      if (!task) {
        return json(res, { error: 'Nội dung nhiệm vụ không được để trống' }, 400, origin)
      }
      const workingDir = ((body.workingDirectory || body.cwd || '') as string).trim() || process.env.HOME || '/home/truong'
      const template = ((body.template || body.templateName || '') as string).trim()

      const scriptCandidates = [
        nodePath.join(serverDir, 'scripts', 'collab-launch.sh'),
        nodePath.join(serverDir, '_original', 'scripts', 'collab-launch.sh'),
        nodePath.join(serverDir, '..', 'scripts', 'collab-launch.sh'),
        nodePath.join(os.homedir(), 'ensemble', 'scripts', 'collab-launch.sh'),
      ]
      const scriptPath = scriptCandidates.find(p => fs.existsSync(p))
      if (!scriptPath) {
        return json(res, { error: 'Không tìm thấy file collab-launch.sh trên hệ thống' }, 500, origin)
      }

      let agents = ''
      if (Array.isArray(body.agents) && body.agents.length > 0) {
        agents = JSON.stringify(body.agents)
      } else if (typeof body.agents === 'string' && body.agents.trim()) {
        agents = body.agents.trim()
      } else {
        agents = (template === 'review' || template === 'review-pro') ? 'agy,agy-pro' : 'agy,agy-worker'
      }

      const { spawn } = await import('child_process')
      const child = spawn(scriptPath, [workingDir, task, agents, template], {
        cwd: workingDir,
        env: { ...process.env, COLLAB_MONITOR: 'none' },
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      })

      let stdoutData = ''
      let teamIdFound = ''

      const teamIdPromise = new Promise<string>((resolve) => {
        const timer = setTimeout(() => resolve(''), 5000)
        child.stdout?.on('data', chunk => {
          const str = chunk.toString()
          stdoutData += str
          const m = str.match(/TEAM_ID=([a-f0-9-]+)/i)
          if (m) {
            clearTimeout(timer)
            teamIdFound = m[1]
            resolve(m[1])
          }
        })
        child.on('exit', () => {
          clearTimeout(timer)
          const m = stdoutData.match(/TEAM_ID=([a-f0-9-]+)/i)
          resolve(m ? m[1] : teamIdFound)
        })
      })

      const teamId = await teamIdPromise
      return json(res, { success: true, teamId: teamId || undefined }, 200, origin)
    }

    // Disband: /api/ensemble/teams/:id/disband
    const disbandMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/disband$/)
    if (disbandMatch && method === 'POST') {
      const result = await disbandTeam(disbandMatch[1])
      if (result.error) return json(res, { error: result.error }, result.status, origin)
      return json(res, result.data, result.status, origin)
    }

    // Feed: /api/ensemble/teams/:id/feed
    const feedMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/feed$/)
    if (feedMatch && method === 'GET') {
      const since = url.searchParams.get('since') || undefined
      const result = getTeamFeed(feedMatch[1], since)
      if (result.error) return json(res, { error: result.error }, result.status, origin)
      return json(res, result.data, result.status, origin)
    }

    // Rename team: POST /api/ensemble/teams/:id/rename
    const renameMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/rename$/)
    if (renameMatch && method === 'POST') {
      const teamId = renameMatch[1]
      let body: Record<string, unknown>
      try {
        body = JSON.parse(await readBody(req))
      } catch {
        return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
      }
      const newName = ((body.name || body.description || '') as string).trim()
      if (!newName) {
        return json(res, { error: 'Tên phiên không được để trống' }, 400, origin)
      }
      const updated = updateTeam(teamId, { description: newName })
      if (!updated) return json(res, { error: 'Team not found' }, 404, origin)
      return json(res, { success: true, team: updated }, 200, origin)
    }

    // Manage team agents: POST /api/ensemble/teams/:id/agents
    const teamAgentsMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/agents$/)
    if (teamAgentsMatch && method === 'POST') {
      const teamId = teamAgentsMatch[1]
      let body: Record<string, unknown>
      try {
        body = JSON.parse(await readBody(req))
      } catch {
        return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
      }
      const team = getTeam(teamId)
      if (!team) return json(res, { error: 'Team not found' }, 404, origin)

      if (Array.isArray(body.agents) && body.agents.length > 0) {
        const previousAgents = team.agents || []
        const updatedAgents = body.agents.map((a: any, idx: number) => ({
          agentId: a.agentId || '',
          name: (a.name || (idx === 0 ? 'Lead' : `Worker-${idx}`)).trim(),
          program: (a.program || (idx === 0 ? 'agy' : 'agy-worker')).trim(),
          role: (a.role || (idx === 0 ? 'lead' : 'worker')).trim(),
          instruction: (a.instruction || '').trim(),
          hostId: a.hostId || '',
          status: a.status || 'active',
        }))

        // Kill tmux sessions for any removed agents
        const updatedNames = new Set(updatedAgents.map(a => a.name.toLowerCase()))
        const removedAgents = previousAgents.filter(a => !updatedNames.has(a.name.toLowerCase()))
        
        if (removedAgents.length > 0) {
          const runtime = getRuntime()
          for (const rem of removedAgents) {
            const sessionName = `${team.name}-${rem.name}`
            try {
              await runtime.killSession(sessionName)
            } catch (err) {
              console.warn(`[Agents] Could not kill session ${sessionName}:`, err)
            }
            appendMessage(teamId, {
              id: uuidv4(),
              teamId,
              from: 'ensemble',
              to: 'team',
              type: 'chat',
              timestamp: new Date().toISOString(),
              content: `🗑️ Tác tử **${rem.name}** (${(rem.role || 'worker').toUpperCase()}) đã được xóa khỏi đội ngũ.`,
            })
          }
        }

        // Notify team feed if any agent role has changed
        for (const up of updatedAgents) {
          const prev = previousAgents.find(p => p.name.toLowerCase() === up.name.toLowerCase())
          if (prev && prev.role && prev.role.toLowerCase() !== up.role.toLowerCase()) {
            appendMessage(teamId, {
              id: uuidv4(),
              teamId,
              from: 'ensemble',
              to: 'team',
              type: 'chat',
              timestamp: new Date().toISOString(),
              content: `🔄 Vai trò của **${up.name}** đã được cập nhật từ **${prev.role.toUpperCase()}** sang **${up.role.toUpperCase()}**. Các thành viên vui lòng điều chỉnh phân công và phối hợp theo vai trò mới.`,
            })
          }
          if (up.instruction && (!prev || prev.instruction !== up.instruction)) {
            appendMessage(teamId, {
              id: uuidv4(),
              teamId,
              from: 'ensemble',
              to: 'team',
              type: 'chat',
              timestamp: new Date().toISOString(),
              content: `🎯 **Nhiệm vụ cụ thể của ${up.name}**: "${up.instruction}"`,
            })
          }
        }

        const updated = updateTeam(teamId, { agents: updatedAgents })

        // If team is active and new agents were added, spin them up
        if (team.status === 'active') {
          const prevNames = new Set(previousAgents.map(a => a.name.toLowerCase()))
          const newlyAdded = updatedAgents.filter(a => !prevNames.has(a.name.toLowerCase()))
          if (newlyAdded.length > 0) {
            await reactivateTeam(teamId)
          }
        }

        return json(res, { success: true, team: updated }, 200, origin)
      }
      return json(res, { error: 'Danh sách Agent không được để trống' }, 400, origin)
    }

    // Start/Launch team: POST /api/ensemble/teams/:id/start
    const startTeamMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/start$/)
    if (startTeamMatch && method === 'POST') {
      const teamId = startTeamMatch[1]
      let body: Record<string, unknown> = {}
      try {
        const raw = await readBody(req)
        if (raw) body = JSON.parse(raw)
      } catch {}

      const team = getTeam(teamId)
      if (!team) return json(res, { error: 'Team không tồn tại' }, 404, origin)

      if (Array.isArray(body.agents) && body.agents.length > 0) {
        const updatedAgents = body.agents.map((a: any, idx: number) => ({
          agentId: a.agentId || '',
          name: (a.name || (idx === 0 ? 'Lead' : `Worker-${idx}`)).trim(),
          program: (a.program || (idx === 0 ? 'agy' : 'agy-worker')).trim(),
          role: (a.role || (idx === 0 ? 'lead' : 'worker')).trim(),
          instruction: (a.instruction || '').trim(),
          hostId: a.hostId || '',
          status: 'active' as const,
        }))
        updateTeam(teamId, { agents: updatedAgents })
      } else if (!team.agents || team.agents.length === 0) {
        return json(res, { error: 'Vui lòng thêm ít nhất 1 Agent vào đội ngũ trước khi khởi chạy.' }, 400, origin)
      }

      const result = await reactivateTeam(teamId)
      if (result.error) return json(res, { error: result.error }, result.status, origin)
      return json(res, result.data, result.status, origin)
    }

    // Upload image attachment: POST /api/ensemble/teams/:id/upload-image
    const uploadMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/upload-image$/)
    if (uploadMatch && method === 'POST') {
      const teamId = uploadMatch[1]
      const team = getTeam(teamId)
      if (!team) return json(res, { error: 'Team not found' }, 404, origin)

      let body: Record<string, unknown>
      try {
        body = JSON.parse(await readBody(req))
      } catch {
        return json(res, { error: 'Bad Request: malformed JSON' }, 400, origin)
      }

      const rawData = (body.data as string) || ''
      const clientFilename = (body.filename as string) || 'screenshot.png'
      if (!rawData) return json(res, { error: 'No image data provided' }, 400, origin)

      const matches = rawData.match(/^data:([A-Za-z-+\/]+);base64,(.+)$/)
      const base64Str = matches ? matches[2] : rawData
      const buffer = Buffer.from(base64Str, 'base64')

      const ext = nodePath.extname(clientFilename) || '.png'
      const safeName = `img_${Date.now()}_${Math.random().toString(36).slice(2, 7)}${ext}`

      const attachDir = nodePath.join(team.workingDirectory || os.homedir(), '.attachments')
      try {
        fs.mkdirSync(attachDir, { recursive: true })
        const destPath = nodePath.join(attachDir, safeName)
        fs.writeFileSync(destPath, buffer)

        const webCacheDir = nodePath.join(os.homedir(), '.ensemble', 'attachments', teamId)
        fs.mkdirSync(webCacheDir, { recursive: true })
        fs.writeFileSync(nodePath.join(webCacheDir, safeName), buffer)

        return json(res, {
          success: true,
          filename: safeName,
          filePath: destPath,
          url: `/api/ensemble/attachments/${teamId}/${safeName}`,
        }, 200, origin)
      } catch (err) {
        console.error('[Upload] Error saving image:', err)
        return json(res, { error: 'Failed to save image attachment' }, 500, origin)
      }
    }

    // Serve attachment image: GET /api/ensemble/attachments/:teamId/:filename
    const attachServeMatch = path.match(/^\/api\/ensemble\/attachments\/([^/]+)\/([^/]+)$/)
    if (attachServeMatch && method === 'GET') {
      const teamId = attachServeMatch[1]
      const filename = attachServeMatch[2]
      const team = getTeam(teamId)
      
      let filePath = ''
      if (team && team.workingDirectory) {
        const p = nodePath.join(team.workingDirectory, '.attachments', filename)
        if (fs.existsSync(p)) filePath = p
      }
      if (!filePath) {
        const p = nodePath.join(os.homedir(), '.ensemble', 'attachments', teamId, filename)
        if (fs.existsSync(p)) filePath = p
      }

      if (filePath && fs.existsSync(filePath)) {
        const ext = nodePath.extname(filePath).toLowerCase()
        const mimeTypes: Record<string, string> = {
          '.png': 'image/png',
          '.jpg': 'image/jpeg',
          '.jpeg': 'image/jpeg',
          '.gif': 'image/gif',
          '.webp': 'image/webp',
          '.svg': 'image/svg+xml',
        }
        res.writeHead(200, {
          'Content-Type': mimeTypes[ext] || 'application/octet-stream',
          'Cache-Control': 'public, max-age=86400',
        })
        fs.createReadStream(filePath).pipe(res)
        return
      }
      return json(res, { error: 'Attachment not found' }, 404, origin)
    }

    // Purge completed / disbanded teams: POST /api/ensemble/teams/purge-completed
    if (path === '/api/ensemble/teams/purge-completed' && method === 'POST') {
      const all = loadTeams()
      let count = 0
      for (const t of all) {
        if (t.status === 'disbanded' || t.status === 'completed' || t.status === 'failed') {
          if (deleteTeam(t.id)) count++
        }
      }
      return json(res, { success: true, count }, 200, origin)
    }

    // Delete single team: POST /api/ensemble/teams/:id/delete or DELETE /api/ensemble/teams/:id
    const deleteMatch = path.match(/^\/api\/ensemble\/teams\/([^/]+)\/delete$/)
    if (deleteMatch && (method === 'POST' || method === 'DELETE')) {
      const teamId = deleteMatch[1]
      try {
        const t = getTeam(teamId)
        if (t && t.status === 'active') {
          await disbandTeam(teamId)
        }
      } catch {}
      const ok = deleteTeam(teamId)
      return json(res, { success: ok, id: teamId }, ok ? 200 : 404, origin)
    }

    // Agents config: /api/ensemble/agents
    if (path === '/api/ensemble/agents' && method === 'GET') {
      const agentsPath = nodePath.join(serverDir, 'agents.json')
      if (fs.existsSync(agentsPath)) {
        try {
          const agentsData = JSON.parse(fs.readFileSync(agentsPath, 'utf8'))
          return json(res, agentsData, 200, origin)
        } catch {
          return json(res, {}, 200, origin)
        }
      }
      return json(res, {}, 200, origin)
    }

    // Model configuration: /api/ensemble/model-config
    if (path === '/api/ensemble/model-config') {
      const agentsPath = nodePath.join(serverDir, 'agents.json')
      const exhaustedFile = nodePath.join(process.env.HOME || '/home/truong', '.ensemble', 'exhausted-models.txt')

      const hasOllama = fs.existsSync('/usr/local/bin/aider-smart') ||
                        fs.existsSync('/usr/bin/aider-smart') ||
                        fs.existsSync('/usr/local/bin/aider') ||
                        fs.existsSync(nodePath.join(process.env.HOME || '/root', '.local/bin/aider'))

      const availableModels = [
        // 1. Gemini 4 Neon (New)
        { id: 'gemini-4-neon-xhigh', name: 'Gemini 4 Neon (XHigh)', group: 'Gemini 4 Neon', desc: 'Siêu tư duy cực hạn (XHigh)' },
        { id: 'gemini-4-neon-high', name: 'Gemini 4 Neon (High)', group: 'Gemini 4 Neon', desc: 'Tư duy cao nhất' },
        { id: 'gemini-4-neon-medium', name: 'Gemini 4 Neon (Medium)', group: 'Gemini 4 Neon', desc: 'Cân bằng tốc độ & trí tuệ' },
        { id: 'gemini-4-neon-low', name: 'Gemini 4 Neon (Low)', group: 'Gemini 4 Neon', desc: 'Tốc độ cao & tiết kiệm token' },

        // 1b. Orchestrator (Neon) (New)
        { id: 'gemini-pro-orchestrator-neon', name: 'Orchestrator (Neon)', group: 'Orchestrator (Neon)', desc: 'Chuyên điều phối tác tử thế hệ mới' },

        // 1c. Gemini 4 Argon
        { id: 'gemini-4-argon-high', name: 'Gemini 4 Argon (High)', group: 'Gemini 4 Argon', desc: 'Tư duy cao nhất' },
        { id: 'gemini-4-argon-medium', name: 'Gemini 4 Argon (Medium)', group: 'Gemini 4 Argon', desc: 'Tư duy tiêu chuẩn' },
        { id: 'gemini-4-argon-low', name: 'Gemini 4 Argon (Low)', group: 'Gemini 4 Argon', desc: 'Nhanh & Nhẹ' },

        // 1d. Gemini 4 Hydrogen
        { id: 'gemini-4-hydrogen-xhigh', name: 'Gemini 4 Hydrogen (XHigh)', group: 'Gemini 4 Hydrogen', desc: 'Siêu tư duy cực hạn (XHigh)' },
        { id: 'gemini-4-hydrogen-high', name: 'Gemini 4 Hydrogen (High)', group: 'Gemini 4 Hydrogen', desc: 'Tư duy nâng cao' },
        { id: 'gemini-4-hydrogen-medium', name: 'Gemini 4 Hydrogen (Medium)', group: 'Gemini 4 Hydrogen', desc: 'Cân bằng thế hệ mới' },
        { id: 'gemini-4-hydrogen-low', name: 'Gemini 4 Hydrogen (Low)', group: 'Gemini 4 Hydrogen', desc: 'Tốc độ cao & tiết kiệm' },

        // 1e. Orchestrator (Argon)
        { id: 'gemini-pro-orchestrator-g1-pro', name: 'Orchestrator (Argon)', group: 'Orchestrator (Argon)', desc: 'Chuyên điều phối nhóm tác tử' },

        // 2. Claude Opus 5.5
        { id: 'claude-opus-5-5-high', name: 'Claude Opus 5.5 (High)', group: 'Claude Opus 5.5', desc: 'Siêu phân tích kiến trúc' },
        { id: 'claude-opus-5-5-medium', name: 'Claude Opus 5.5 (Medium)', group: 'Claude Opus 5.5', desc: 'Cân bằng cao cấp' },
        { id: 'claude-opus-5-5-low', name: 'Claude Opus 5.5 (Low)', group: 'Claude Opus 5.5', desc: 'Phản hồi nhanh' },

        // 3. Claude Sonnet 5.5
        { id: 'claude-sonnet-5-5-high', name: 'Claude Sonnet 5.5 (High)', group: 'Claude Sonnet 5.5', desc: 'Lập trình chuyên sâu' },
        { id: 'claude-sonnet-5-5-medium', name: 'Claude Sonnet 5.5 (Medium)', group: 'Claude Sonnet 5.5', desc: 'Cân bằng & code chuẩn' },
        { id: 'claude-sonnet-5-5-low', name: 'Claude Sonnet 5.5 (Low)', group: 'Claude Sonnet 5.5', desc: 'Tốc độ cao' },

        // 4. Claude Pro (Claude Code CLI - Gói thuê bao Claude Pro)
        { id: 'cc-opus-high', name: 'Claude Opus (Pro) (High)', group: 'Claude Opus (Pro)', desc: 'Claude Pro: Siêu phân tích kiến trúc' },
        { id: 'cc-opus-medium', name: 'Claude Opus (Pro) (Medium)', group: 'Claude Opus (Pro)', desc: 'Claude Pro: Cân bằng cao cấp' },
        { id: 'cc-opus-low', name: 'Claude Opus (Pro) (Low)', group: 'Claude Opus (Pro)', desc: 'Claude Pro: Phản hồi nhanh' },
        { id: 'cc-sonnet-high', name: 'Claude Sonnet (Pro) (High)', group: 'Claude Sonnet (Pro)', desc: 'Claude Pro: Lập trình chuyên sâu' },
        { id: 'cc-sonnet-medium', name: 'Claude Sonnet (Pro) (Medium)', group: 'Claude Sonnet (Pro)', desc: 'Claude Pro: Cân bằng & code chuẩn' },
        { id: 'cc-sonnet-low', name: 'Claude Sonnet (Pro) (Low)', group: 'Claude Sonnet (Pro)', desc: 'Claude Pro: Tốc độ cao' },

        // 5. Gemini 3.8 Flash
        { id: 'gemini-3.8-flash-high', name: 'Gemini 3.8 Flash (High)', group: 'Gemini 3.8 Flash', desc: 'Suy luận cao, dồi dào Quota' },
        { id: 'gemini-3.8-flash-medium', name: 'Gemini 3.8 Flash (Medium)', group: 'Gemini 3.8 Flash', desc: 'Đa phương thức, tốc độ cao' },
        { id: 'gemini-3.8-flash-low', name: 'Gemini 3.8 Flash (Low)', group: 'Gemini 3.8 Flash', desc: 'Siêu nhẹ, tiết kiệm token' },

        // 6. GPT-OSS 120B
        { id: 'gpt-oss-120b-medium', name: 'GPT-OSS 120B (Medium)', group: 'GPT-OSS 120B', desc: 'Mô hình mã nguồn mở 120B' },

        ...(hasOllama ? [
          // 7. Ollama Local (chỉ hiện khi máy đã cài đặt kết nối Ollama/Aider)
          { id: 'ollama-gemma', name: 'Ollama Gemma 4 (12B Local)', group: 'Local Ollama', desc: 'Chạy trực tiếp trên máy chủ nội bộ (Không tốn quota)' },
          { id: 'ollama-qwen', name: 'Ollama Qwen 3 Coder (30B Local)', group: 'Local Ollama', desc: 'Chuyên lập trình & kiến trúc mã nguồn 30B (Mạng nội bộ)' }
        ] : []),
      ]

      if (method === 'GET') {
        let currentAgents: Record<string, any> = {}
        if (fs.existsSync(agentsPath)) {
          try { currentAgents = JSON.parse(fs.readFileSync(agentsPath, 'utf8')) } catch {}
        }
        let exhausted: string[] = []
        if (fs.existsSync(exhaustedFile)) {
          try {
            exhausted = fs.readFileSync(exhaustedFile, 'utf8').split('\n').map((s: string) => s.trim()).filter(Boolean)
          } catch {}
        }

        const getModel = (key: string) => {
          const prog = currentAgents[key]
          if (prog && prog.flags) {
            const idx = prog.flags.indexOf('--model')
            if (idx !== -1 && prog.flags[idx + 1]) return prog.flags[idx + 1]
          }
          return ''
        }

        return json(res, {
          availableModels,
          roles: {
            lead: getModel('agy') || 'gemini-4-argon-low',
            worker: getModel('agy-worker') || 'gemini-3.8-flash-low',
            reviewer: getModel('agy-pro') || 'gemini-4-argon-low',
          },
          exhaustedModels: exhausted,
        }, 200, origin)
      }

      if (method === 'POST') {
        try {
          const body = JSON.parse(await readBody(req))
          let currentAgents: Record<string, any> = {}
          if (fs.existsSync(agentsPath)) {
            try { currentAgents = JSON.parse(fs.readFileSync(agentsPath, 'utf8')) } catch {}
          }

          const setModel = (key: string, model: string) => {
            if (currentAgents[key] && currentAgents[key].flags) {
              const a = currentAgents[key]
              if (model.startsWith('cc-')) {
                // Model Claude Pro -> chạy qua Claude Code CLI
                a.command = 'claude-smart'
                a.flags = ['--permission-mode', 'auto', '--model', model]
                a.readyMarker = '❯'
                a.unsetEnv = ['ANTHROPIC_API_KEY']
              } else if (model.startsWith('ollama') || model.includes('gemma') || model.includes('qwen')) {
                // Model Ollama Local -> chạy qua aider-smart
                a.command = 'aider-smart'
                let targetM = model
                if (model === 'ollama-gemma') targetM = 'ollama/gemma4:12b'
                else if (model === 'ollama-qwen') targetM = 'ollama/qwen3-coder:30b'
                a.flags = ['--model', targetM]
                a.readyMarker = '>'
                a.unsetEnv = []
              } else {
                // Model Antigravity -> chạy qua agy-smart
                if (a.command === 'claude-smart' || a.command === 'aider-smart') {
                  a.command = 'agy-smart'
                  a.flags = ['--dangerously-skip-permissions', '--model', model]
                  a.readyMarker = '? for shortcuts'
                  a.unsetEnv = ['GEMINI_API_KEY', 'GOOGLE_API_KEY']
                } else {
                  const idx = a.flags.indexOf('--model')
                  if (idx !== -1) a.flags[idx + 1] = model
                }
              }
            }
          }

          if (body.roles) {
            if (body.roles.lead) setModel('agy', body.roles.lead)
            if (body.roles.worker) setModel('agy-worker', body.roles.worker)
            if (body.roles.reviewer) setModel('agy-pro', body.roles.reviewer)
          }

          fs.writeFileSync(agentsPath, JSON.stringify(currentAgents, null, 2), 'utf8')
          try {
            fs.writeFileSync('/mnt/d/Ensemble/_original/agents.json', JSON.stringify(currentAgents, null, 2), 'utf8')
          } catch {}

          if (body.clearExhausted) {
            fs.writeFileSync(exhaustedFile, '', 'utf8')
          } else if (Array.isArray(body.exhaustedModels)) {
            fs.writeFileSync(exhaustedFile, body.exhaustedModels.join('\n') + '\n', 'utf8')
          }

          return json(res, { success: true }, 200, origin)
        } catch (err) {
          return json(res, { error: String(err) }, 400, origin)
        }
      }
    }

    // Web Dashboard UI
    if (path === '/' || path === '/index.html' || path === '/dashboard') {
      const publicIndex = nodePath.join(serverDir, 'public', 'index.html')
      if (fs.existsSync(publicIndex)) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
        fs.createReadStream(publicIndex).pipe(res)
        return
      }
    }
    if (path.startsWith('/public/')) {
      const rel = path.slice('/public/'.length)
      const target = nodePath.join(serverDir, 'public', rel)
      if (fs.existsSync(target) && fs.statSync(target).isFile()) {
        const ext = nodePath.extname(target).toLowerCase()
        const mimeTypes: Record<string, string> = {
          '.html': 'text/html; charset=utf-8',
          '.js': 'application/javascript; charset=utf-8',
          '.css': 'text/css; charset=utf-8',
          '.svg': 'image/svg+xml',
          '.png': 'image/png',
          '.ico': 'image/x-icon',
          '.json': 'application/json',
        }
        res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'text/plain' })
        fs.createReadStream(target).pipe(res)
        return
      }
    }

    json(res, { error: 'Not found' }, 404, origin)
  } catch (err) {
    console.error('[Server] Error:', err)
    json(res, { error: 'Internal server error' }, 500, origin)
  }
})

server.on('error', (err: NodeJS.ErrnoException) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[Ensemble] Port ${PORT} is already in use on ${HOST}. Stop the other process or set ENSEMBLE_PORT to a different port.`)
    process.exit(1)
  }

  console.error('[Ensemble] Server failed to start:', err)
  process.exit(1)
})

server.listen(PORT, HOST, () => {
  console.log(`[Ensemble] Server running on http://${HOST}:${PORT}`)
  console.log(`[Ensemble] Health: http://localhost:${PORT}/api/v1/health`)
})
