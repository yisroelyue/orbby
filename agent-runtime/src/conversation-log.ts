import { appendFile, mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

export async function conversationLog(id: string | undefined, type: string, data: unknown) {
  if (!id) return;
  try {
    const dir = join(homedir(), '.orbby', 'task', id);
    await mkdir(dir, { recursive: true });
    const isMessage = type === 'request' || type === 'response' || type === 'llm.request' || type === 'llm.response';
    const file = isMessage ? 'messages.log' : 'events.log';
    const title = type === 'request' ? 'REQUEST' : type === 'llm.request' ? 'LLM REQUEST' : type === 'llm.response' ? 'LLM RESPONSE' : 'RESPONSE';
    const separator = isMessage ? `\n\n==================== ${title} ====================\n` : '';
    await appendFile(join(dir, file), separator + JSON.stringify({ time: new Date().toISOString(), type, data }) + '\n', 'utf8');
  } catch (_) {}
}
