import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const workspaceFile = join(homedir(), '.orbby', 'setting', 'workspace.json');

/** /cd 持久化的工作区；未切换过（首次启动）返回 null，回落 ORBBY_WORKSPACE 与桌面默认 */
export function loadWorkspace(): string | null {
  try {
    const value = JSON.parse(readFileSync(workspaceFile, 'utf8')) as { workspace?: unknown };
    return typeof value.workspace === 'string' && value.workspace.trim() ? value.workspace : null;
  } catch {
    return null;
  }
}

export function saveWorkspace(path: string): void {
  const directory = join(homedir(), '.orbby', 'setting');
  mkdirSync(directory, { recursive: true });
  writeFileSync(workspaceFile, `${JSON.stringify({ workspace: path }, null, 2)}\n`, 'utf8');
}
