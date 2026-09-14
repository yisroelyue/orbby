import { attachmentKind } from './content-adapter.js';
/** 单文件提取文本字符上限（保护上下文窗口） */
export const MAX_EXTRACT_CHARS_PER_FILE = 50_000;
/** 单次请求全部文本附件的总字符预算 */
export const MAX_EXTRACT_CHARS_TOTAL = 120_000;
/** 单文件提取超时（大 PDF 首次解析较慢） */
export const EXTRACT_TIMEOUT_MS = 15_000;
/** 截断并显式标注"内容不完整"，避免半份文档被模型当全量自信分析 */
function truncate(text, limit, fileName) {
    if (text.length <= limit)
        return text;
    return `${text.slice(0, limit)}\n\n[注意：「${fileName}」共 ${text.length} 字符，超出单文件上限 ${MAX_EXTRACT_CHARS_PER_FILE}，仅保留前 ${limit} 字符，内容不完整]`;
}
function withTimeout(promise, fileName) {
    return Promise.race([
        promise,
        new Promise((_, reject) => setTimeout(() => reject(new Error(`「${fileName}」提取超时（${EXTRACT_TIMEOUT_MS}ms）`)), EXTRACT_TIMEOUT_MS)),
    ]);
}
/** 文本附件解码：按 BOM 识别 UTF-8/UTF-16，无 BOM 按 UTF-8（GBK 等旧编码会乱码，第一版限制） */
function decodeTextFile(buffer) {
    if (buffer.length >= 3 && buffer[0] === 0xEF && buffer[1] === 0xBB && buffer[2] === 0xBF) {
        return buffer.subarray(3).toString('utf8');
    }
    if (buffer.length >= 2 && buffer[0] === 0xFF && buffer[1] === 0xFE) {
        return buffer.subarray(2).toString('utf16le');
    }
    if (buffer.length >= 2 && buffer[0] === 0xFE && buffer[1] === 0xFF) {
        const swapped = Buffer.from(buffer.subarray(2));
        swapped.swap16();
        return swapped.toString('utf16le');
    }
    return buffer.toString('utf8');
}
function extractPlainText(buffer) {
    return { text: decodeTextFile(buffer), info: '文本全文内嵌' };
}
/** PDF 按页提取文本并标注页码（unpdf 惰性加载：纯 JS 封装，无原生编译依赖） */
async function extractPdfText(buffer) {
    const { extractText, getDocumentProxy } = await import('unpdf');
    const pdf = await getDocumentProxy(new Uint8Array(buffer));
    const { totalPages, text } = await extractText(pdf, { mergePages: false });
    const pages = Array.isArray(text) ? text : [text];
    const joined = pages
        .map((page, i) => `--- 第 ${i + 1} 页 ---\n${String(page ?? '').trim()}`)
        .join('\n\n');
    return { text: joined, info: `已提取文本（共 ${totalPages} 页）` };
}
/**
 * 附件预提取：文本/PDF 附件在 Node 侧统一提取为文本，写入 extractedText /
 * extractedInfo（图片附件跳过）；在内容组装（toUserContent）前调用。
 * 提取失败同样以文本呈现给模型，不让附件静默消失。
 */
export async function extractAttachments(attachments, signal) {
    let budget = MAX_EXTRACT_CHARS_TOTAL;
    for (const attachment of attachments) {
        const kind = attachmentKind(attachment.mimeType);
        if (kind !== 'text' && kind !== 'document')
            continue;
        signal?.throwIfAborted();
        const buffer = Buffer.from(attachment.data, 'base64');
        try {
            const result = attachment.mimeType === 'application/pdf'
                ? await withTimeout(extractPdfText(buffer), attachment.fileName)
                : extractPlainText(buffer);
            if (budget <= 0) {
                attachment.extractedText = `[注意：「${attachment.fileName}」未纳入：本次请求文本附件总量已达上限 ${MAX_EXTRACT_CHARS_TOTAL} 字符]`;
                attachment.extractedInfo = '超出总量预算，未纳入';
                continue;
            }
            const limit = Math.min(MAX_EXTRACT_CHARS_PER_FILE, budget);
            attachment.extractedText = truncate(result.text, limit, attachment.fileName);
            attachment.extractedInfo = result.info + (result.text.length > limit ? '，已截断' : '');
            budget -= Math.min(result.text.length, limit);
        }
        catch (error) {
            const reason = error instanceof Error ? error.message : String(error);
            attachment.extractedText = `[附件提取失败：${reason}；请告知用户无法读取该附件]`;
            attachment.extractedInfo = '提取失败';
        }
    }
}
