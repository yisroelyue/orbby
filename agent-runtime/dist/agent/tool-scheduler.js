export async function executeToolCalls(registry, calls, context, signal, maxParallel = 4, onEvent) {
    context.signal = signal;
    const results = [];
    let cursor = 0;
    const worker = async () => { while (cursor < calls.length) {
        const index = cursor++;
        const call = calls[index];
        if (signal.aborted) {
            results[index] = { id: call.id, name: call.name, output: '', error: { code: 'ABORTED_BEFORE_DISPATCH', message: 'Tool call aborted before dispatch' } };
            continue;
        }
        onEvent?.('tool.start', { id: call.id, name: call.name, arguments: call.arguments });
        try {
            const result = await registry.execute(call.name, call.arguments, context);
            const value = result && typeof result === 'object' && 'output' in result ? result : { output: result };
            results[index] = { id: call.id, name: call.name, output: value.output, changes: value.changes };
            onEvent?.('tool.result', { id: call.id, name: call.name, output: value.output, changes: value.changes ?? [] });
        }
        catch (error) {
            const message = String(error);
            results[index] = { id: call.id, name: call.name, output: '', error: { code: 'TOOL_ERROR', message } };
            onEvent?.('tool.error', { id: call.id, name: call.name, message });
        }
    } };
    await Promise.all(Array.from({ length: Math.min(maxParallel, calls.length) }, () => worker()));
    return results;
}
