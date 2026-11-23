import { describe, expect, it } from 'vitest'
import { detectLiveGate } from '../lib/startup-gates'
import { isShellCommand } from '../lib/agent-runtime'

// Real screen text from Claude Code 2.1.283 in a new, untrusted directory.
// The cursor defaults to "No, exit": a bare Enter closes Claude and leaves an
// empty shell behind.
const CLAUDE_TRUST_NO_SELECTED = [
  '────────────────────────────────────────────────────────────────────────────────',
  ' Accessing workspace:',
  ' /private/tmp/ensrepro',
  ' Quick safety check: Is this a project you created or one you trust? (Like your',
  ' own code, a well-known open source project, or work from your team). If not,',
  " take a moment to review what's in this folder first.",
  " Claude Code'll be able to read, edit, and execute files here.",
  ' Security guide',
  ' ❯ No, exit',
  '   Yes, I trust this folder',
  ' Enter to confirm · Esc to cancel',
].join('\n')

const CLAUDE_TRUST_YES_SELECTED = CLAUDE_TRUST_NO_SELECTED
  .replace(' ❯ No, exit', '   No, exit')
  .replace('   Yes, I trust this folder', ' ❯ Yes, I trust this folder')

const CLAUDE_READY_TAIL = [
  '',
  '❯ Try "fix typecheck errors"',
  '────────────────────────────────────────────────────────────────────────────────',
  '  [Opus] │ ensrepro',
  '  Context ░░░░░░ 0%',
  '  1 CLAUDE.md | 5 MCPs | 13 hooks',
  '  ⏵⏵ bypass permissions on (shift+tab to cycle)',
].join('\n')

// Real screen text from Claude Code 2.1.330 started with
// CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 in a trusted directory.
const CLAUDE_CODE_MODE_NO_SELECTED = [
  '────────────────────────────────────────────────────────────────────────────────',
  '  Code Mode (experimental)',
  '  In Code Mode, Claude works by writing and running JavaScript that calls its tools, instead of calling them one at a time.',
  '  This is an early experiment. It can behave differently from normal Claude Code, and it may change or be removed in any',
  '  release. Remote Control, Claude in Chrome and computer use are off in Code Mode.',
  '  A session that you start in Code Mode can be resumed only with Code Mode on. If you turn Code Mode off, turn it on again to',
  "  resume the session. Where Code Mode isn't available, the session can't be resumed: cloud sessions and the Claude apps can't",
  '  continue it, and older versions of Claude Code may open it but not work properly in it.',
  '  Sessions start in the same permission mode as without Code Mode, which can be auto mode where it\'s available. In auto mode,',
  "  the safety check reads each piece of JavaScript once, before it runs. It doesn't check each tool call that the code then",
  "  makes, so it can't see values that the code works out as it runs.",
  '  ❯ No, start without it',
  '    Yes, turn on Code Mode',
  '  Tell us how it goes with /feedback',
  '  Enter to confirm · Esc to start without it',
].join('\n')

const CLAUDE_CODE_MODE_YES_SELECTED = CLAUDE_CODE_MODE_NO_SELECTED
  .replace('  ❯ No, start without it', '    No, start without it')
  .replace('    Yes, turn on Code Mode', '  ❯ Yes, turn on Code Mode')

describe('detectLiveGate', () => {
  it('chooses "Yes, turn on Code Mode" when the cursor is on "No, start without it"', () => {
    expect(detectLiveGate(CLAUDE_CODE_MODE_NO_SELECTED)).toEqual({ name: 'code mode opt-in', keys: 'down-enter' })
  })

  it('confirms the Code Mode dialog with Enter once "Yes" is selected', () => {
    expect(detectLiveGate(CLAUDE_CODE_MODE_YES_SELECTED)).toEqual({ name: 'code mode opt-in', keys: 'enter' })
  })

  it('ignores an answered Code Mode dialog in the scrollback above a running agent', () => {
    const filler = Array.from({ length: 20 }, (_, i) => `  regel ${i}`).join('\n')
    expect(detectLiveGate(`${CLAUDE_CODE_MODE_YES_SELECTED}\n${filler}\n${CLAUDE_READY_TAIL}`)).toBeNull()
  })

  it('bevestigt de agy-trustvraag met de voorgeselecteerde Yes-optie', () => {
    const pane = 'Do you trust the contents of this project?\n> Yes, I trust this folder'
    expect(detectLiveGate(pane)).toEqual({ name: 'trust prompt', keys: 'enter' })
  })

  it('kiest "Yes, I trust this folder" als de cursor op "No, exit" staat', () => {
    expect(detectLiveGate(CLAUDE_TRUST_NO_SELECTED)).toEqual({ name: 'trust prompt', keys: 'down-enter' })
  })

  it('volstaat met Enter als "Yes" al geselecteerd is', () => {
    expect(detectLiveGate(CLAUDE_TRUST_YES_SELECTED)).toEqual({ name: 'trust prompt', keys: 'enter' })
  })

  it('negeert een oude trust-dialoog in de scrollback boven een draaiende agent', () => {
    const filler = Array.from({ length: 20 }, (_, i) => `  regel ${i}`).join('\n')
    const pane = `${CLAUDE_TRUST_YES_SELECTED}\n${filler}\n${CLAUDE_READY_TAIL}`
    expect(detectLiveGate(pane)).toBeNull()
  })

  it('herkent de codex-trustvraag nog steeds', () => {
    const pane = 'Do you trust the contents of this directory?\n› 1. Yes, continue\n  2. No, quit\nPress enter to continue'
    expect(detectLiveGate(pane)).toEqual({ name: 'trust prompt', keys: 'enter' })
  })

  it('herkent de bypass-waarschuwing', () => {
    const pane = 'WARNING: Claude Code running in Bypass Permissions mode\n❯ 1. No, exit\n  2. Yes, I accept'
    expect(detectLiveGate(pane)).toEqual({ name: 'bypass permissions warning', keys: 'down-enter' })
  })
})

describe('isShellCommand', () => {
  it.each(['zsh', '-zsh', 'bash', 'sh', 'fish', '/bin/zsh'])('%s is een shell', cmd => {
    expect(isShellCommand(cmd)).toBe(true)
  })

  it.each(['claude', '2.1.283', 'codex', 'node', 'cat', ''])('%s is geen shell', cmd => {
    expect(isShellCommand(cmd)).toBe(false)
  })
})
