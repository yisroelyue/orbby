import { WsAttachment } from '../protocol.js';

/** 统一内部内容块：文本 / 图片（Base64） */
export type TextPart = { type: 'text'; text: string };
export type ImagePart = { type: 'image'; mediaType: string; data: string };
export type ContentPart = TextPart | ImagePart;

/** LLM 消息的统一内容格式：纯文本字符串或内容块数组 */
export type LlmContent = string | ContentPart[];

/** 视觉模型支持的图片 mime（与 Flutter 侧 ClipboardImageService 白名单一致） */
export const SUPPORTED_IMAGE_MIME = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);

/** 文本类附件统一以此 mime 上报（真实类型由 fileName 扩展名体现） */
export const SUPPORTED_TEXT_MIME = new Set(['text/plain']);

/** 二进制文档 mime（Node 侧提取为文本，见 attachment-extractor.ts） */
export const SUPPORTED_DOCUMENT_MIME = new Set(['application/pdf']);

export type AttachmentKind = 'image' | 'text' | 'document';

/** 附件分类：决定 Base64 上限与提取路径；未知 mime 返回 null */
export function attachmentKind(mimeType: string): AttachmentKind | null {
  if (SUPPORTED_IMAGE_MIME.has(mimeType)) return 'image';
  if (SUPPORTED_TEXT_MIME.has(mimeType)) return 'text';
  if (SUPPORTED_DOCUMENT_MIME.has(mimeType)) return 'document';
  return null;
}

/** 单次请求最多附件数（与 Flutter 侧 ChatAttachmentController.maxCount 一致） */
export const MAX_ATTACHMENTS = 4;

/** 单附件 Base64 上限按类型：图片约 10MB 原图 / 文本约 5MB / PDF 约 20MB（与 Flutter 侧限制对应） */
const MAX_BASE64_LENGTH: Record<AttachmentKind, number> = { image: 14_000_000, text: 7_000_000, document: 28_000_000 };

/**
 * Node 侧兜底校验：过滤不支持/超限的附件。
 * Flutter 已限一层（数量/mime/大小），这里防旧版本客户端或直接调用。
 */
export function sanitizeAttachments(raw: unknown): WsAttachment[] {
  if (!Array.isArray(raw)) return [];
  const out: WsAttachment[] = [];
  for (const item of raw.slice(0, MAX_ATTACHMENTS)) {
    if (!item || typeof item !== 'object') continue;
    const a = item as Record<string, unknown>;
    const mimeType = String(a.mimeType ?? '');
    const data = typeof a.data === 'string' ? a.data : '';
    const kind = attachmentKind(mimeType);
    if (!kind || !data) continue;
    if (data.length > MAX_BASE64_LENGTH[kind]) continue;
    const width = typeof a.width === 'number' ? a.width : undefined;
    const height = typeof a.height === 'number' ? a.height : undefined;
    out.push({
      id: String(a.id ?? ''),
      fileName: String(a.fileName ?? 'file'),
      mimeType,
      data,
      ...(width !== undefined ? {width} : {}),
      ...(height !== undefined ? {height} : {}),
    });
  }
  return out;
}

/** 附件说明：告知模型内容已内嵌、并列出文件名与形态，防止模型去本地搜索"源文件" */
function attachmentNote(attachments: WsAttachment[]): string {
  const list = attachments.map(a => {
    const desc = attachmentKind(a.mimeType) === 'image' ? '图片，原图内嵌' : `文档，${a.extractedInfo ?? '已提取文本'}`;
    return `- ${a.fileName}（${a.mimeType}｜${desc}）`;
  }).join('\n');
  return `用户随本消息附带了 ${attachments.length} 个附件，内容已直接内嵌在本消息中（图片为 Base64 原图，文档为提取后的文本），可直接查看分析，无需在工作区或本地磁盘搜索"源文件"（除非用户明确要求操作本地文件）：\n${list}`;
}

/** 文档附件的内容块：头部标注 + 提取出的文本 */
function documentPart(a: WsAttachment): TextPart {
  return {type: 'text', text: `[附件: ${a.fileName}｜${a.extractedInfo ?? '已提取文本'}]\n${a.extractedText ?? ''}`};
}

/** 统一用户消息内容：图片块、文档文本块在前，正文（含附件说明）在后 */
export function toUserContent(message: string, attachments: WsAttachment[] = []): LlmContent {
  if (!attachments.length) return message;
  const parts: ContentPart[] = attachments
    .filter(a => attachmentKind(a.mimeType) === 'image')
    .map(a => ({type: 'image' as const, mediaType: a.mimeType, data: a.data}));
  for (const a of attachments) {
    if (attachmentKind(a.mimeType) !== 'image') parts.push(documentPart(a));
  }
  const text = [attachmentNote(attachments), message].filter(Boolean).join('\n\n');
  if (text) parts.push({type: 'text', text});
  return parts;
}

/** 归一化任意 content 为纯文本：历史轮只回放文字，不发图片（省视觉 token） */
export function toPlainText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .filter((part): part is TextPart => !!part && typeof part === 'object' && (part as ContentPart).type === 'text')
      .map(part => part.text ?? '')
      .join('\n');
  }
  return content == null ? '' : String(content);
}

// ─── OpenAI-compatible ────────────────────────────────────────────────────

/** OpenAI 多模态 content：string 或 text/image_url 块数组 */
export function toOpenAiContent(content: LlmContent): string | Array<Record<string, unknown>> {
  if (typeof content === 'string') return content;
  return content.map(part =>
    part.type === 'text'
      ? {type: 'text', text: part.text}
      : {type: 'image_url', image_url: {url: `data:${part.mediaType};base64,${part.data}`, detail: 'auto'}},
  );
}

// ─── Anthropic ────────────────────────────────────────────────────────────

/** Anthropic content blocks：string 转单 text 块，多模态转 image/text 块 */
export function toAnthropicBlocks(content: LlmContent): Array<Record<string, unknown>> {
  if (typeof content === 'string') {
    return content ? [{type: 'text', text: content}] : [];
  }
  return content.map(part =>
    part.type === 'text'
      ? {type: 'text', text: part.text}
      : {type: 'image', source: {type: 'base64', media_type: part.mediaType, data: part.data}},
  );
}
