import { conversationLog } from '../conversation-log.js';
import { toOpenAiContent, toAnthropicBlocks } from './content-adapter.js';
/** Anthropic Messages API 的 max_tokens 必填；4096 与 Dart 侧 LLMClient 一致 */
const ANTHROPIC_MAX_TOKENS = 4096;
/** provider 判定：Flutter 显式传 platform 时以其为准；旧客户端按 URL 兜底 */
export function isAnthropicProvider(config) {
    const platform = (config.platform ?? '').toLowerCase();
    if (platform)
        return platform === 'anthropic';
    return config.url.toLowerCase().includes('anthropic');
}
function anthropicHeaders(config) {
    return { 'content-type': 'application/json', 'x-api-key': config.apiKey, 'anthropic-version': '2023-06-01' };
}
function openAiHeaders(config) {
    return { 'content-type': 'application/json', authorization: `Bearer ${config.apiKey}` };
}
function toOpenAiMessages(messages) {
    return messages.map(m => ({
        role: m.role,
        content: m.content == null ? null : toOpenAiContent(m.content),
        ...(m.tool_call_id ? { tool_call_id: m.tool_call_id } : {}),
        ...(m.tool_calls ? { tool_calls: m.tool_calls } : {}),
    }));
}
function toAnthropicMessages(messages) {
    const out = [];
    // Anthropic 的 tool 结果必须作为 user 消息里的 tool_result 块，连续 tool 消息合并
    let toolResults = null;
    const flushToolResults = () => {
        if (toolResults && toolResults.length)
            out.push({ role: 'user', content: toolResults });
        toolResults = null;
    };
    for (const m of messages) {
        if (m.role === 'system')
            continue;
        if (m.role === 'tool') {
            toolResults ??= [];
            toolResults.push({ type: 'tool_result', tool_use_id: m.tool_call_id ?? '', content: m.content ?? '' });
            continue;
        }
        flushToolResults();
        const blocks = toAnthropicBlocks((m.content ?? ''));
        if (m.role === 'assistant' && Array.isArray(m.tool_calls)) {
            for (const call of m.tool_calls) {
                let input = {};
                try {
                    input = JSON.parse(call.function.arguments || '{}');
                }
                catch {
                    input = {};
                }
                blocks.push({ type: 'tool_use', id: call.id, name: call.function.name, input });
            }
        }
        if (blocks.length)
            out.push({ role: m.role === 'assistant' ? 'assistant' : 'user', content: blocks });
    }
    flushToolResults();
    return out;
}
/** 入参 tools 是 OpenAI function 格式；Anthropic 需要 input_schema 字段名 */
function toAnthropicTools(tools) {
    if (!tools.length)
        return undefined;
    return tools
        .map(t => ({ name: t.function.name, description: t.function.description ?? '', input_schema: t.function.parameters ?? { type: 'object', properties: {} } }));
}
function buildOpenAiBody(config, messages, tools, stream) {
    return { model: config.model, messages: toOpenAiMessages(messages), tools: tools.length ? tools : undefined, stream };
}
function buildAnthropicBody(config, messages, tools, stream) {
    const system = messages
        .filter(m => m.role === 'system' && typeof m.content === 'string')
        .map(m => m.content)
        .filter(Boolean)
        .join('\n\n');
    const anthropicTools = toAnthropicTools(tools);
    return {
        model: config.model,
        max_tokens: ANTHROPIC_MAX_TOKENS,
        messages: toAnthropicMessages(messages),
        ...(system ? { system } : {}),
        ...(anthropicTools ? { tools: anthropicTools } : {}),
        ...(stream ? { stream: true } : {}),
    };
}
/** SSE 逐行迭代（跨 provider 共享）：按 \r?\n 切分并保留残行 */
async function* sseLines(body) {
    let buffer = '';
    for await (const chunk of body) {
        buffer += Buffer.from(chunk).toString('utf8');
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? '';
        for (const line of lines)
            yield line;
    }
}
export async function streamComplete(config, messages, tools, signal, onText) {
    if (!config.url || !config.apiKey || !config.model)
        throw new Error('LLM configuration is incomplete');
    const anthropic = isAnthropicProvider(config);
    const body = anthropic
        ? buildAnthropicBody(config, messages, tools, true)
        : buildOpenAiBody(config, messages, tools, true);
    void conversationLog(config.conversationId, 'llm.request', { url: config.url, apiKey: config.apiKey, model: config.model, body });
    const response = await fetch(config.url, { method: 'POST', signal, headers: anthropic ? anthropicHeaders(config) : openAiHeaders(config), body: JSON.stringify(body) });
    if (!response.ok || !response.body)
        throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`), { code: 'LLM_REQUEST_ERROR' });
    const calls = new Map();
    let content = '';
    for await (const line of sseLines(response.body)) {
        if (!line.startsWith('data:'))
            continue;
        const raw = line.slice(5).trim();
        if (raw === '[DONE]')
            continue;
        const event = JSON.parse(raw);
        if (anthropic) {
            if (event.type === 'content_block_start' && event.content_block?.type === 'tool_use') {
                calls.set(Number(event.index ?? 0), { id: String(event.content_block.id ?? ''), name: String(event.content_block.name ?? ''), args: '' });
            }
            else if (event.type === 'content_block_delta') {
                const delta = event.delta ?? {};
                if (delta.type === 'text_delta' && delta.text) {
                    content += delta.text;
                    onText(delta.text);
                }
                else if (delta.type === 'input_json_delta' && delta.partial_json) {
                    const call = calls.get(Number(event.index ?? 0));
                    if (call)
                        call.args += delta.partial_json;
                }
            }
        }
        else {
            const delta = event.choices?.[0]?.delta;
            if (delta?.content) {
                content += delta.content;
                onText(delta.content);
            }
            for (const item of delta?.tool_calls ?? []) {
                const index = Number(item.index ?? 0);
                const call = calls.get(index) ?? { id: String(item.id ?? `call-${index}`), name: '', args: '' };
                if (item.id)
                    call.id = String(item.id);
                if (item.function?.name)
                    call.name += item.function.name;
                if (item.function?.arguments)
                    call.args += item.function.arguments;
                calls.set(index, call);
            }
        }
    }
    const result = { content, toolCalls: [...calls.values()].filter(call => call.name).map(call => ({ id: call.id, name: call.name, arguments: JSON.parse(call.args || '{}') })) };
    void conversationLog(config.conversationId, 'llm.response', result);
    return result;
}
export async function complete(config, messages, tools, signal) {
    if (!config.url || !config.apiKey || !config.model)
        throw new Error('LLM configuration is incomplete');
    const anthropic = isAnthropicProvider(config);
    const body = anthropic
        ? buildAnthropicBody(config, messages, tools, false)
        : buildOpenAiBody(config, messages, tools, false);
    const response = await fetch(config.url, { method: 'POST', signal, headers: anthropic ? anthropicHeaders(config) : openAiHeaders(config), body: JSON.stringify(body) }).catch(error => { throw Object.assign(new Error(`LLM connection failed: ${String(error)}`), { code: 'LLM_CONNECTION_ERROR' }); });
    if (!response.ok)
        throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`), { code: 'LLM_REQUEST_ERROR', status: response.status });
    const raw = await response.json();
    if (anthropic) {
        const blocks = raw.content ?? [];
        const content = blocks.filter(b => b?.type === 'text').map(b => b.text ?? '').join('');
        const toolCalls = blocks.filter(b => b?.type === 'tool_use').map(b => ({ id: String(b.id), name: String(b.name), arguments: (b.input ?? {}) }));
        return { content, toolCalls };
    }
    const message = raw.choices?.[0]?.message;
    if (!message)
        throw new Error('LLM response did not contain a message');
    const toolCalls = (message.tool_calls ?? []).map((call) => ({ id: String(call.id), name: String(call.function.name), arguments: JSON.parse(call.function.arguments || '{}') }));
    return { content: message.content ?? '', toolCalls };
}
