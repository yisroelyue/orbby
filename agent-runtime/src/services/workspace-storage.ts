import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const workspaceFile = join(homedir(), '.orbby', 'setting', 'workspace.json');
/** 会话级工作区条目上限：超出按写入顺序淘汰最旧的，防止长期累积 */
const MAX_SESSION_ENTRIES = 50;

interface WorkspaceFile { workspace?: unknown; sessions?: Record<string, unknown>; }

function readAll(): WorkspaceFile {
  try {
    return JSON.parse(readFileSync(workspaceFile, 'utf8')) as WorkspaceFile;
  } catch {
    return {};
  }
}
function writeAll(value: WorkspaceFile): void {
  const directory = join(homedir(), '.orbby', 'setting');
  mkdirSync(directory, { recursive: true });
  writeFileSync(workspaceFile, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}
function cleanSessions(value: unknown): Record<string, string> {
  if (!value || typeof value !== 'object') return {};
  const result: Record<string, string> = {};
  for (const [key, item] of Object.entries(value)) {
    if (typeof item === 'string' && item.trim()) result[key] = item;
  }
  return result;
}

/** 全局默认工作区（最近一次 /cd 的目录）；未切换过（首次启动）返回 null，回落 ORBBY_WORKSPACE 与桌面默认 */
export function loadWorkspace(): string | null {
  const value = readAll().workspace;
  return typeof value === 'string' && value.trim() ? value : null;
}

/** 会话专属工作区：同一会话重开（sessionId 不变）恢复上次 /cd 的目录 */
export function loadSessionWorkspace(sessionId: string): string | null {
  const value = readAll().sessions?.[sessionId];
  return typeof value === 'string' && value.trim() ? value : null;
}

/**
 * 持久化会话工作区（多会话并发：各会话独立记录，互不覆盖）。
 * 顶层默认值同步刷新为新路径，让新会话的初始工作区 = 最近一次 /cd 的目录（保持单会话体验）。
 */
export function saveSessionWorkspace(sessionId: string, path: string): void {
  const file = readAll();
  const sessions = cleanSessions(file.sessions);
  delete sessions[sessionId]; // 先删再写刷新键序，LRU 按 JSON 键插入顺序淘汰
  sessions[sessionId] = path;
  const entries = Object.entries(sessions);
  if (entries.length > MAX_SESSION_ENTRIES) {
    for (const [key] of entries.slice(0, entries.length - MAX_SESSION_ENTRIES)) delete sessions[key];
  }
  writeAll({ ...file, workspace: path, sessions });
}
