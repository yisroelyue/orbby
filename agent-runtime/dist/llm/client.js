import { conversationLog } from '../conversation-log.js';
export async function streamComplete(config, messages, tools, signal, onText) {
    if (!config.url || !config.apiKey || !config.model)
        throw new Error('LLM configuration is incomplete');
    const body = { model: config.model, messages, tools: tools.length ? tools : undefined, stream: true };
    void conversationLog(config.conversationId, 'llm.request', { url: config.url, apiKey: config.apiKey, model: config.model, body });
    const response = await fetch(config.url, { method: 'POST', signal, headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apiKey}` }, body: JSON.stringify(body) });
    if (!response.ok || !response.body)
        throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`), { code: 'LLM_REQUEST_ERROR' });
    const calls = new Map();
    let content = '';
    let buffer = '';
    for await (const chunk of response.body) {
        buffer += Buffer.from(chunk).toString('utf8');
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? '';
        for (const line of lines) {
            if (!line.startsWith('data:'))
                continue;
            const raw = line.slice(5).trim();
            if (raw === '[DONE]')
                continue;
            const delta = JSON.parse(raw).choices?.[0]?.delta;
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
    const result = { content, toolCalls: [...calls.values()].map(call => ({ id: call.id, name: call.name, arguments: JSON.parse(call.args || '{}') })) };
    void conversationLog(config.conversationId, 'llm.response', result);
    return result;
}
export async function complete(config, messages, tools, signal) {
    if (!config.url || !config.apiKey || !config.model)
        throw new Error('LLM configuration is incomplete');
    const response = await fetch(config.url, { method: 'POST', signal, headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apiKey}` }, body: JSON.stringify({ model: config.model, messages, tools: tools.length ? tools : undefined, stream: false }) }).catch(error => { throw Object.assign(new Error(`LLM connection failed: ${String(error)}`), { code: 'LLM_CONNECTION_ERROR' }); });
    if (!response.ok)
        throw Object.assign(new Error(`LLM request failed: ${response.status} ${await response.text()}`), { code: 'LLM_REQUEST_ERROR', status: response.status });
    const body = await response.json();
    const message = body.choices?.[0]?.message;
    if (!message)
        throw new Error('LLM response did not contain a message');
    const toolCalls = (message.tool_calls ?? []).map((call) => ({ id: String(call.id), name: String(call.function.name), arguments: JSON.parse(call.function.arguments || '{}') }));
    return { content: message.content ?? '', toolCalls };
}
