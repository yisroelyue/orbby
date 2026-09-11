import { promises as fs } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, relative, sep } from 'node:path';
import { AgentQuestion } from '../protocol.js';

export type Permission = 'read' | 'write' | 'execute';
type Entry = { path: string; permissions: Permission[] };

export class WorkspacePermissionService {
  private readonly file = resolve(homedir(), '.orbby', 'permissions.json');
  private entries: Entry[] = [];
  private loaded = false;
  async ensure(path: string, permission: Permission, askUser?: (questions: AgentQuestion[]) => Promise<string[][]>) {
    const target = resolve(path); await this.load();
    if (this.entries.some(e => this.allows(e, target, permission))) return;
    if (!askUser) throw new Error(`Permission denied: ${target}`);
    const answer = await askUser([{question:`允许 Agent 对目录 ${target} 执行 ${permission} 操作吗？`, header:'目录权限', type:'choice', options:[{label:'允许'},{label:'拒绝'}]}]);
    // 结构化答案：第一个问题的第一个选中项精确等于"允许"才放行
    if (answer?.[0]?.[0] !== '允许') throw new Error(`Permission denied: ${target}`);
    const entry = this.entries.find(e => e.path === target) ?? {path:target, permissions:[]};
    if (!this.entries.includes(entry)) this.entries.push(entry); if (!entry.permissions.includes(permission)) entry.permissions.push(permission); await this.save();
  }
  private allows(e: Entry, target: string, permission: Permission) { const rel = relative(e.path, target); return e.permissions.includes(permission) && (rel === '' || (!rel.startsWith('..') && !rel.includes(`..${sep}`))); }
  private async load() { if (this.loaded) return; this.loaded = true; try { this.entries = JSON.parse(await fs.readFile(this.file, 'utf8')) as Entry[]; } catch {} }
  private async save() { await fs.mkdir(resolve(homedir(), '.orbby'), {recursive:true}); await fs.writeFile(this.file, JSON.stringify(this.entries, null, 2), 'utf8'); }
  async grant(path: string, permissions: Permission[]) { await this.load(); const target = resolve(path); const entry = this.entries.find(e => e.path === target) ?? {path:target, permissions:[]}; if (!this.entries.includes(entry)) this.entries.push(entry); for (const permission of permissions) if (!entry.permissions.includes(permission)) entry.permissions.push(permission); await this.save(); }
  async grantFromExplicitIntent(message: string, workspacePath: string) {
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
  }
}
