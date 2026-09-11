export function reply(type, requestId, sessionId, payload = {}) {
    return { type, requestId, ...(sessionId ? { sessionId } : {}), payload };
}
