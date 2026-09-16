import { resolve } from 'node:path';
import { AgentQuestion } from '../protocol.js';

export type Permission = 'read' | 'write' | 'execute';
type Entry = { path: string; permissions: Permission[] };

export class WorkspacePermissionService {
  private mode: 'ask' | 'all' | 'read' = 'ask';
  setMode(mode: string) { if (mode === 'all' || mode === 'read' || mode === 'ask') this.mode = mode; }
  async ensure(path: string, permission: Permission, askUser?: (questions: AgentQuestion[]) => Promise<string[][]>) {
    const target = resolve(path);
    if (this.mode === 'all' || (this.mode === 'read' && permission === 'read')) return;
    if (!askUser) throw new Error(`Permission denied: ${target}`);
    const answer = await askUser([{question:`允许 Agent 对目录 ${target} 执行 ${permission} 操作吗？`, header:'目录权限', type:'choice', options:[{label:'允许'},{label:'拒绝'}]}]);
    // 结构化答案：第一个问题的第一个选中项精确等于"允许"才放行
    if (answer?.[0]?.[0] !== '允许') throw new Error(`Permission denied: ${target}`);
  }
  async clear() {}
  async list(): Promise<Entry[]> { return []; }
  async grantFromExplicitIntent(message: string, workspacePath: string) {
    return;
    /*
    const lower = message.toLowerCase();
    const writing = /创建|新建|写入|修改|编辑|追加|覆盖|保存|create|write|edit|append|update|modify/.test(lower);
    const reading = /读取|查看|打开|分析|内容|read|查看/.test(lower);
    if (!writing && !reading) return;
    const permissions: Permission[] = writing ? ['write'] : ['read'];
    const targets = new Set<string>();
    if (/桌面|desktop/.test(lower)) targets.add(resolve(homedir(), 'Desktop'));
    if (/工作区|项目目录|workspace|project/.test(lower)) targets.add(resolve(workspacePath));
    const paths = message.match(/[A-Za-z]:[\\/][^\s"'，。；;]+/g) ?? [];
    for (const path of paths) targets.add(resolve(path.replace(/[。，；;]+$/, '')));
    for (const target of targets) await this.grant(target, permissions);
    */
  }
}
