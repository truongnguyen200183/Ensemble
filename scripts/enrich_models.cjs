const fs = require('fs');
const path = require('path');

function inferLayer(id, group) {
  const s = (id + ' ' + (group || '')).toLowerCase();
  if (s.includes('ollama') || s.includes('local')) return 'Local';
  if (s.includes('120b') || s.includes('gpt-oss')) return 'Tier 4';
  if (s.includes('xhigh') || s.includes('high') || s.includes('orchestrator') || s.includes('opus')) return 'Tier 1';
  if (s.includes('medium') || s.includes('sonnet')) return 'Tier 2';
  if (s.includes('low') || s.includes('flash')) return 'Tier 3';
  return 'Tier 2';
}

const INFO_CATALOG = {
  'gemini-4-neon': {
    coreStrengths: [
      'Thế hệ Gemini 4 mới nhất, tối ưu đặc biệt cho tác vụ lập trình & chu trình trao đổi tác tử (agentic loop).',
      'Khả năng tư duy logic sâu tiệm cận Argon nhưng độ trễ (latency) thấp hơn đáng kể và ít bị nghẽn thời gian chờ.'
    ],
    speedQuota: ['Nhanh & Mượt', 'Quota tính chung cho toàn bộ họ Neon (XHigh / High / Med / Low).'],
    ensembleRec: ['XHigh / High: Vị trí LEAD hoặc REVIEWER.', 'Medium: Vị trí WORKER cho các bài toán phức tạp.', 'Low: WORKER chạy nhanh, tiết kiệm token.']
  },
  'gemini-pro-orchestrator-neon': {
    coreStrengths: [
      'Mô hình chuyên dụng được Google huấn luyện riêng cho vai trò Điều phối tác tử (Swarm Coordinator / Orchestrator) trên nền kiến trúc Neon.',
      'Phân tích yêu cầu, bóc tách nhiệm vụ con (subtasks) và tổng hợp kết quả giữa các tác tử với tốc độ tức thì.'
    ],
    speedQuota: ['Rất nhanh & Tức thì', 'Tối ưu hóa độ trễ phản hồi turn-by-turn trong các phiên cộng tác dài.'],
    ensembleRec: ['Cực kỳ lý tưởng cho vị trí LEAD (Kiến trúc sư trưởng / Lập kế hoạch).']
  },
  'gemini-pro-orchestrator-g1-pro': {
    coreStrengths: [
      'Mô hình chuyên dụng điều phối nhóm tác tử xây dựng trên nền tảng Gemini 4 Argon.',
      'Phân tích yêu cầu cẩn trọng, suy luận chặt chẽ từng bước triển khai kế hoạch.'
    ],
    speedQuota: ['Trung bình / Nặng', 'Cần chú ý hạn mức Quota tuần của họ Argon.'],
    ensembleRec: ['Vị trí LEAD: Phù hợp khi điều phối các dự án đòi hỏi kiến trúc chuẩn mực cao.']
  },
  'gemini-4-argon': {
    coreStrengths: [
      'Mô hình suy luận và tính toán mạnh mẽ nhất của Google.',
      'Khả năng giải quyết các thuật toán phức tạp, suy luận trừu tượng và kiến trúc sâu rộng.'
    ],
    speedQuota: ['Chậm hơn & Quota nghiêm ngặt', 'Dễ chạm trần hạn mức nếu gọi liên tục nhiều lượt.'],
    ensembleRec: ['LEAD hoặc REVIEWER cho các dự án quy mô lớn cần độ chính xác tối đa.']
  },
  'gemini-4-hydrogen': {
    coreStrengths: [
      'Thế hệ mô hình thế hệ 4 cân bằng giữa suy luận nâng cao và hiệu năng xử lý.',
      'Khả năng duy trì mạch logic xuyên suốt trong các phiên làm việc dài.'
    ],
    speedQuota: ['Nhanh hơn Argon', 'Quota tính chung cho họ Hydrogen (XHigh / High / Med / Low).'],
    ensembleRec: ['XHigh / High: LEAD / REVIEWER.', 'Medium / Low: WORKER hiệu năng cao.']
  },
  'claude-opus-5-5': {
    coreStrengths: [
      'Khả năng phân tích kiến trúc hệ thống đỉnh cao, tổng hợp thông tin đa chiều và phản biện sắc sảo.',
      'Phát hiện lỗi tiềm ẩn và thiết kế module rất xuất sắc.'
    ],
    speedQuota: ['Trung bình', 'Hạn mức tiêu thụ theo gói Claude Pro / Claude Code.'],
    ensembleRec: ['Lựa chọn hàng đầu cho REVIEWER (Chuyên gia phản biện) hoặc LEAD.']
  },
  'claude-sonnet-5-5': {
    coreStrengths: [
      'Mô hình lập trình số 1 hiện nay: tạo diff code chính xác, tuân thủ convention, sửa lỗi nhanh.',
      'Hiểu ngữ cảnh mã nguồn cực tốt, sinh code sạch và hoàn chỉnh.'
    ],
    speedQuota: ['Rất nhanh & Ổn định', 'Theo hạn mức gói Claude Pro / Claude Code.'],
    ensembleRec: ['Lựa chọn hoàn hảo nhất cho WORKER (Lập trình viên thực thi).']
  },
  'gemini-3.8-flash': {
    coreStrengths: [
      'Tốc độ phản hồi cực kỳ nhanh, đa phương thức (multimodal), xử lý context lớn nhẹ nhàng.',
      'Chi phí token thấp và hạn mức gọi API cực kỳ hào phóng.'
    ],
    speedQuota: ['Siêu nhanh & Dồi dào Quota nhất', 'Hầu như không bao giờ lo bị nghẽn hoặc hết Quota.'],
    ensembleRec: ['WORKER tiêu chuẩn xử lý các tác vụ thực thi nhanh chóng.', 'Trạm cứu sinh (Auto-fallback) an toàn khi các model Bậc 1 & 2 hết hạn mức.']
  },
  'gpt-oss-120b': {
    coreStrengths: [
      'Mô hình mã nguồn mở kích thước lớn 120B tham số, phục vụ nghiên cứu và đa dạng hóa góc nhìn.',
      'Tạo góc nhìn đối chiếu độc lập không phụ thuộc nhà cung cấp duy nhất.'
    ],
    speedQuota: ['Khá nhanh', 'Phụ thuộc vào máy chủ cộng đồng.'],
    ensembleRec: ['WORKER hoặc REVIEWER dự phòng để tạo góc nhìn đối chiếu độc lập.']
  },
  'ollama-gemma': {
    coreStrengths: [
      'Chạy trực tiếp trên server Ollama nội bộ (192.168.86.23:11434) qua Aider CLI.',
      'Hoàn toàn miễn phí, riêng tư, không giới hạn request hay quota từ bên ngoài.',
      'Hỗ trợ chế độ tư duy (thinking mode) và chỉnh sửa tệp tin tự động.'
    ],
    speedQuota: ['Xử lý cục bộ', 'Không phụ thuộc vào kết nối Internet hay hạn mức API ngoài.'],
    ensembleRec: ['Lựa chọn tối ưu cho WORKER hoặc tác vụ tự động chạy nền không lo cạn quota.']
  },
  'ollama-qwen': {
    coreStrengths: [
      'Mô hình chuyên dụng về lập trình và kiến trúc mã nguồn 30B tham số.',
      'Khả năng đọc hiểu repo lớn, refactor, sinh code và fix bug cực kỳ chính xác.',
      'Chạy trực tiếp trên server Ollama nội bộ qua Aider CLI, hoàn toàn miễn phí và riêng tư.'
    ],
    speedQuota: ['Xử lý cục bộ', 'Không phụ thuộc vào kết nối Internet hay hạn mức API ngoài.'],
    ensembleRec: ['Lựa chọn hàng đầu cho WORKER (Lập trình viên) khi triển khai trong mạng nội bộ.']
  }
};

function getModelGroupKey(id) {
  const s = String(id).toLowerCase();
  if (s.includes('orchestrator-neon')) return 'gemini-pro-orchestrator-neon';
  if (s.includes('orchestrator')) return 'gemini-pro-orchestrator-g1-pro';
  if (s.includes('neon')) return 'gemini-4-neon';
  if (s.includes('hydrogen')) return 'gemini-4-hydrogen';
  if (s.includes('argon')) return 'gemini-4-argon';
  if (s.includes('opus')) return 'claude-opus-5-5';
  if (s.includes('sonnet')) return 'claude-sonnet-5-5';
  if (s.includes('flash')) return 'gemini-3.8-flash';
  if (s.includes('120b') || s.includes('gpt-oss')) return 'gpt-oss-120b';
  if (s.includes('qwen')) return 'ollama-qwen';
  if (s.includes('ollama') || s.includes('gemma')) return 'ollama-gemma';
  return 'gemini-4-neon';
}

const files = [
  path.join(__dirname, '..', 'models.json'),
  path.join(__dirname, '..', '_original', 'models.json')
];

for (const f of files) {
  if (fs.existsSync(f)) {
    const list = JSON.parse(fs.readFileSync(f, 'utf8'));
    const updated = list.map(m => {
      const layer = m.layer || inferLayer(m.id, m.group);
      const key = getModelGroupKey(m.id);
      const info = m.info || INFO_CATALOG[key] || {};
      return {
        id: m.id,
        name: m.name,
        group: m.group,
        desc: m.desc || '',
        layer,
        apiKey: m.apiKey || '',
        info
      };
    });
    fs.writeFileSync(f, JSON.stringify(updated, null, 2), 'utf8');
    console.log('Successfully updated', f, 'with', updated.length, 'models');
  }
}
