import { promises as fs } from 'node:fs';
import { dirname, resolve, relative, sep } from 'node:path';
function safePath(input, root) {
    const path = resolve(root, input);
    if (path.split(sep).includes('.git'))
        throw new Error('Access to .git is not allowed');
    return path;
}
function params(properties, required = []) { return { type: 'object', properties, required }; }
function diff(path, before, after, operation) {
    const oldLines = (before ?? '').split(/\r?\n/);
    const newLines = (after ?? '').split(/\r?\n/);
    let start = 0;
    while (start < oldLines.length && start < newLines.length && oldLines[start] === newLines[start])
        start++;
    let endOld = oldLines.length - 1, endNew = newLines.length - 1;
    while (endOld >= start && endNew >= start && oldLines[endOld] === newLines[endNew]) {
        endOld--;
        endNew--;
    }
    const removed = oldLines.slice(start, endOld + 1), added = newLines.slice(start, endNew + 1);
    const lines = [`--- a/${path}`, `+++ b/${path}`, `@@ -${start + 1},${removed.length} +${start + 1},${added.length} @@`, ...removed.map(x => `-${x}`), ...added.map(x => `+${x}`)];
    return { output: `${operation}d ${path}`, changes: [{ path, operation, diff: lines.join('\n'), additions: added.length, deletions: removed.length }] };
}
function displayPath(path, workspace) { const value = relative(workspace, path).replaceAll(sep, '/'); return value.startsWith('../') ? path.replaceAll(sep, '/') : value; }
/** edit 匹配失败时的纠偏提示：按首行去空白比较找到文件中的实际行，暴露真实缩进，避免模型盲猜缩进反复重试 */
function editHint(before, old) {
    const first = old.split('\n').map(line => line.trim()).find(Boolean);
    if (!first)
        return '';
    const hits = [];
    before.split('\n').forEach((line, i) => { if (line.trim() === first)
        hits.push(`${i + 1}: ${JSON.stringify(line)}`); });
    return hits.length ? `。首行去空白后在文件中可匹配 ${hits.length} 处，实际行（引号内为真实内容与缩进）：\n${hits.slice(0, 5).join('\n')}\n请按实际行的真实缩进重试，或改用不含行首空白的唯一子串。` : '';
}
async function change(path, display, operation, before, action) { await action(); const after = operation === 'delete' ? null : await fs.readFile(path, 'utf8'); return diff(display, before, after, operation); }
export function registerFilesystemTools(registry) {
    const text = { type: 'string' };
    registry.register({ name: 'read', description: 'Read a text file with optional line range.', parameters: params({ path: text, startLine: { type: 'integer' }, endLine: { type: 'integer' } }, ['path']), async execute(args, ctx) {
            const path = safePath(String(args.path), ctx.workspacePath);
            await ctx.permissions?.ensure(path, 'read', ctx.askUser);
            const value = await fs.readFile(path, 'utf8');
            const lines = value.split(/\r?\n/);
            const start = Math.max(1, Number(args.startLine ?? 1));
            const end = Math.min(lines.length, Number(args.endLine ?? lines.length));
            // 行号与内容必须用制表符分隔：空格分隔符会被模型并入行首缩进（缩进 +2），构造出的 edit oldString 永远匹配不上
            return lines.slice(start - 1, end).map((line, i) => `${String(start + i).padStart(6)}\t${line}`).join('\n');
        } });
    registry.register({ name: 'write', description: 'Create or overwrite a UTF-8 text file.', parameters: params({ path: text, content: text }, ['path', 'content']), async execute(args, ctx) {
            const path = safePath(String(args.path), ctx.workspacePath);
            await ctx.permissions?.ensure(path, 'write', ctx.askUser);
            let before = null;
            try {
                before = await fs.readFile(path, 'utf8');
            }
            catch { }
            return change(path, displayPath(path, ctx.workspacePath), before === null ? 'create' : 'edit', before, async () => { await fs.mkdir(dirname(path), { recursive: true }); await fs.writeFile(path, String(args.content), 'utf8'); });
        } });
    registry.register({ name: 'edit', description: 'Replace an exact string in a UTF-8 text file.', parameters: params({ path: text, oldString: text, newString: text, replaceAll: { type: 'boolean' } }, ['path', 'oldString', 'newString']), async execute(args, ctx) {
            const path = safePath(String(args.path), ctx.workspacePath);
            await ctx.permissions?.ensure(path, 'write', ctx.askUser);
            const raw = await fs.readFile(path, 'utf8');
            // read 展示时已把 CRLF 归一化为 LF，模型构造的 oldString 只会含 \n：统一在 LF 视图上匹配，写回时还原文件原换行风格，否则 CRLF 文件的多行替换永远匹配不上
            const crlf = raw.includes('\r\n');
            const before = raw.replaceAll('\r\n', '\n');
            const old = String(args.oldString).replaceAll('\r\n', '\n');
            const replacement = String(args.newString).replaceAll('\r\n', '\n');
            const count = before.split(old).length - 1;
            if (count === 0)
                throw new Error(`Edit target was not found${editHint(before, old)}`);
            if (count > 1 && !args.replaceAll)
                throw new Error(`Edit target is ambiguous (${count} occurrences; pass replaceAll:true to replace all)`);
            const merged = before.replace(args.replaceAll ? new RegExp(old.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g') : old, replacement);
            const after = crlf ? merged.replaceAll('\n', '\r\n') : merged;
            await fs.writeFile(path, after, 'utf8');
            return diff(displayPath(path, ctx.workspacePath), before, merged, 'edit');
        } });
    registry.register({ name: 'delete', description: 'Delete a file after permission approval.', parameters: params({ path: text }, ['path']), async execute(args, ctx) {
            const path = safePath(String(args.path), ctx.workspacePath);
            await ctx.permissions?.ensure(path, 'write', ctx.askUser);
            const before = await fs.readFile(path, 'utf8');
            await fs.unlink(path);
            return diff(displayPath(path, ctx.workspacePath), before, null, 'delete');
        } });
    registry.register({ name: 'glob', description: 'Find files under the workspace by a simple name pattern.', parameters: params({ pattern: text }, ['pattern']), async execute(args, ctx) {
            const result = [];
            const pattern = String(args.pattern).replaceAll('*', '');
            async function walk(dir) { for (const e of await fs.readdir(dir, { withFileTypes: true })) {
                if (e.name === 'node_modules' || e.name === '.git')
                    continue;
                const p = resolve(dir, e.name);
                if (e.isDirectory())
                    await walk(p);
                else if (e.name.includes(pattern))
                    result.push(relative(ctx.workspacePath, p));
            } }
            await walk(ctx.workspacePath);
            return result.join('\n') || 'No matches';
        } });
    registry.register({ name: 'grep', description: 'Search text files under the workspace.', parameters: params({ query: text }, ['query']), async execute(args, ctx) {
            const result = [];
            const query = String(args.query);
            async function walk(dir) { for (const e of await fs.readdir(dir, { withFileTypes: true })) {
                if (e.name === 'node_modules' || e.name === '.git')
                    continue;
                const p = resolve(dir, e.name);
                if (e.isDirectory())
                    await walk(p);
                else {
                    try {
                        const lines = (await fs.readFile(p, 'utf8')).split(/\r?\n/);
                        lines.forEach((l, i) => { if (l.includes(query))
                            result.push(`${relative(ctx.workspacePath, p)}:${i + 1}:${l}`); });
                    }
                    catch { }
                }
            } }
            await walk(ctx.workspacePath);
            return result.join('\n') || 'No matches';
        } });
    registry.register({ name: 'str_replace_editor', description: 'View, create, replace, or insert text in files.', parameters: params({ command: { type: 'string', enum: ['view', 'create', 'str_replace', 'insert'] }, path: text, old_str: text, new_str: text, file_text: text, insert_line: { type: 'integer' } }, ['command', 'path']), async execute(args, ctx) {
            const raw = String(args.command);
            const command = raw === 'replace' ? 'str_replace' : raw;
            if (command === 'view')
                return registry.execute('read', { path: args.path }, ctx);
            if (command === 'create')
                return registry.execute('write', { path: args.path, content: args.file_text ?? '' }, ctx);
            if (command === 'str_replace')
                return registry.execute('edit', { path: args.path, oldString: args.old_str, newString: args.new_str ?? '', replaceAll: false }, ctx);
            if (command === 'insert') {
                const path = safePath(String(args.path), ctx.workspacePath);
                await ctx.permissions?.ensure(path, 'write', ctx.askUser);
                const raw = await fs.readFile(path, 'utf8');
                const crlf = raw.includes('\r\n');
                const lines = raw.split(/\r?\n/);
                const line = Math.max(0, Math.min(lines.length, Number(args.insert_line ?? lines.length)));
                lines.splice(line, 0, String(args.new_str ?? '').replaceAll('\r\n', '\n'));
                const merged = lines.join('\n');
                await fs.writeFile(path, crlf ? merged.replaceAll('\n', '\r\n') : merged, 'utf8');
                return diff(displayPath(path, ctx.workspacePath), raw, merged, 'edit');
            }
            throw new Error(`Unsupported editor command: ${command}`);
        } });
}
