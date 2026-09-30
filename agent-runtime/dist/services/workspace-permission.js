import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
/** 技能资源目录（~/.orbby/skills）的只读白名单：引用展开时注入的目录路径
 *  LLM 会主动去读，逐次弹确认体验太差；写入与执行仍走原授权模型。 */
function isUnderSkillsDir(target) {
    const root = join(homedir(), '.orbby', 'skills').toLowerCase();
    const lower = target.toLowerCase();
    return lower === root || lower.startsWith(`${root}\\`) || lower.startsWith(`${root}/`);
}
export class WorkspacePermissionService {
    mode = 'ask';
    setMode(mode) { if (mode === 'all' || mode === 'read' || mode === 'ask')
        this.mode = mode; }
    async ensure(path, permission, askUser) {
        const target = resolve(path);
        if (this.mode === 'all' || (this.mode === 'read' && permission === 'read'))
            return;
        if (permission === 'read' && isUnderSkillsDir(target))
            return;
        if (!askUser)
            throw new Error(`Permission denied: ${target}`);
        const answer = await askUser([{ question: `允许 Agent 对目录 ${target} 执行 ${permission} 操作吗？`, header: '目录权限', type: 'choice', options: [{ label: '允许' }, { label: '拒绝' }] }]);
        // 结构化答案：第一个问题的第一个选中项精确等于"允许"才放行
        if (answer?.[0]?.[0] !== '允许')
            throw new Error(`Permission denied: ${target}`);
    }
    async clear() { }
    async list() { return []; }
    async grantFromExplicitIntent(message, workspacePath) {
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
