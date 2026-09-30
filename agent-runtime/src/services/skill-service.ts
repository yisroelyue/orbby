import { homedir } from 'node:os';
import { join } from 'node:path';
import { readdir, readFile } from 'node:fs/promises';
import { mkdirSync, watch, type FSWatcher } from 'node:fs';

/** 技能条目：与 Flutter 侧 SkillService 共用 ~/.orbby/skills/ 目录，两种形态：
 *  - 目录式（推荐）：子目录内 SKILL.md 为元数据+正文，同目录其余文件是
 *    技能资源（脚本/模板等），dir 记录绝对路径供注入；
 *  - 散装单文件：一个 md 一个技能，dir 为 null。
 *  Flutter 只解析元数据做面板展示；本模块额外读正文与资源清单做引用展开。 */
export interface SkillEntry {
  name: string;
  description: string;
  /** 目录式技能的绝对路径；散装为 null */
  dir: string | null;
  body: string;
}

let cachedSkills: SkillEntry[] | null = null;

function skillsDir() { return join(homedir(), '.orbby', 'skills'); }

/** 清空技能缓存（/reload-skill 命令经 skills.reload 消息触发，或目录
 *  监听发现变化时自动触发）：下次 expandSkillRefs 时重新扫目录，
 *  加/改技能文件无需重启 runtime */
export function clearSkillCache() { cachedSkills = null; }

let skillsWatcher: FSWatcher | null = null;
let watchDebounce: NodeJS.Timeout | null = null;

/** 监听技能目录变化（LLM 创建技能 / 用户手改文件后自动热加载）：
 *  变更防抖合并后回调 onChange——由 server 层清缓存并广播 skills.changed
 *  通知 Flutter 重扫面板，等效自动 /reload-skill。
 *  runtime 生命周期内单 watcher；目录不存在先创建（与 Flutter seed 不冲突）；
 *  watcher 异常（目录被删/占用）时丢弃并在 5s 后重建，期间靠 /reload-skill 兜底。 */
export function startSkillsWatch(onChange: () => void): void {
  if (skillsWatcher) return;
  try { mkdirSync(skillsDir(), { recursive: true }); } catch { return; }
  try {
    const watcher = watch(skillsDir(), { recursive: true }, () => {
      if (watchDebounce) clearTimeout(watchDebounce);
      watchDebounce = setTimeout(() => { watchDebounce = null; onChange(); }, 1000);
    });
    skillsWatcher = watcher;
    watcher.on('error', () => {
      if (skillsWatcher !== watcher) return;
      skillsWatcher = null;
      // 先摘掉监听再 close，防止 close 事件二次触发重建
      watcher.removeAllListeners();
      try { watcher.close(); } catch { /* 已关闭 */ }
      setTimeout(() => startSkillsWatch(onChange), 5000);
    });
  } catch { skillsWatcher = null; }
}

/** 扫描技能目录并按名称排序；同名技能目录式优先。目录不存在或不可读
 *  返回空列表（目录的创建与示例技能 seed 由 Flutter 侧负责）。
 *  结果缓存在内存——与 Flutter 面板一致，runtime 生命周期内不热更新。 */
export async function loadSkills(): Promise<SkillEntry[]> {
  if (cachedSkills) return cachedSkills;
  const root = skillsDir();
  const loose = new Map<string, SkillEntry>();
  const dirBased = new Map<string, SkillEntry>();
  try {
    const entries = await readdir(root, { withFileTypes: true });
    for (const entry of entries) {
      try {
        if (entry.isDirectory()) {
          const parsed = await parseSkillFile(join(root, entry.name, 'SKILL.md'), entry.name);
          if (parsed) dirBased.set(parsed.name.toLowerCase(), { ...parsed, dir: join(root, entry.name) });
        } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.md')) {
          const dot = entry.name.lastIndexOf('.');
          const stem = dot > 0 ? entry.name.slice(0, dot) : entry.name;
          const parsed = await parseSkillFile(join(root, entry.name), stem);
          if (parsed) loose.set(parsed.name.toLowerCase(), { ...parsed, dir: null });
        }
      } catch { /* 单个技能解析失败跳过，不影响其余技能 */ }
    }
  } catch { /* 目录不可读按无技能处理 */ }
  // 展开顺序保证同名时目录式覆盖散装
  const skills = [...new Map([...loose, ...dirBased]).values()];
  skills.sort((a, b) => a.name.localeCompare(b.name));
  cachedSkills = skills;
  return skills;
}

interface ParsedSkill { name: string; description: string; body: string }

/** 解析技能文件的 frontmatter 与正文；name 优先取 frontmatter、缺省用
 *  fallbackName（目录式传目录名、散装传文件名 stem）；name 含空白的跳过
 *  （@ 引用片段以空白截止，无法被完整输入）。文件不可读返回 null。 */
async function parseSkillFile(file: string, fallbackName: string): Promise<ParsedSkill | null> {
  let text: string;
  try { text = await readFile(file, 'utf8'); } catch { return null; }
  const parsed = parseFrontmatter(text);
  const name = (parsed.name ?? fallbackName).trim();
  if (!name || /\s/.test(name)) return null;
  return { name, description: parsed.description?.trim() ?? '', body: parsed.body.trim() };
}

/** 极简 frontmatter 解析：首行 '---' 到下一个 '---' 之间的 `key: value`，其余为正文 */
function parseFrontmatter(text: string): { name?: string; description?: string; body: string } {
  const lines = text.split(/\r?\n/);
  if (lines[0]?.trim() !== '---') return { body: text };
  const meta: Record<string, string> = {};
  let i = 1;
  for (; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === '---') { i++; break; }
    const colon = line.indexOf(':');
    if (colon <= 0) continue;
    meta[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
  }
  return { name: meta.name, description: meta.description, body: lines.slice(i).join('\n') };
}

/** 消息文本中的 @技能名 引用：@ 后到空白或常见中英文标点截止 */
const SKILL_REF = /@([^\s@,.，。;；:：!！?？()（）\[\]【】"'“”「」]+)/g;

/** 引用串 → 技能：先精确匹配；失败则取"是该串前缀"的技能中最长者。
 *  中文没有空格分隔习惯（"用@磁盘扫描整理一下"引用与正文粘连），
 *  截断出的引用串会带上后续正文导致精确匹配必然失败，前缀兜底
 *  让手打路径与面板选中路径（自动补尾随空格）都能展开。 */
function resolveSkillRef(token: string, byName: Map<string, SkillEntry>): SkillEntry | null {
  const lower = token.toLowerCase();
  const exact = byName.get(lower);
  if (exact) return exact;
  let best: SkillEntry | null = null;
  for (const [name, skill] of byName) {
    if (name.length > 0 && lower.startsWith(name) && (!best || name.length > best.name.length)) best = skill;
  }
  return best;
}

/** 把文本中已注册技能的 @ 引用展开为消息末尾附加的技能指令块（同名去重）；
 *  原句保持不变（LLM 仍能看到用户引用了哪些技能），未注册的 @xxx 原样保留。
 *  目录式技能附带资源目录绝对路径与一层文件清单——LLM 可经命令工具以
 *  绝对路径执行其中的脚本，不必由技能作者硬编码路径。
 *  无有效引用时返回原文。 */
export async function expandSkillRefs(text: string): Promise<string> {
  const skills = await loadSkills();
  if (!skills.length || !text.includes('@')) return text;
  const byName = new Map(skills.map(s => [s.name.toLowerCase(), s]));
  const referenced: SkillEntry[] = [];
  for (const match of text.matchAll(SKILL_REF)) {
    const skill = resolveSkillRef(match[1], byName);
    if (skill && !referenced.some(r => r.name === skill.name)) referenced.push(skill);
  }
  if (!referenced.length) return text;
  const blocks: string[] = [];
  for (const skill of referenced) blocks.push(await buildSkillBlock(skill));
  const names = referenced.map(s => `@${s.name}`).join(' ');
  return `${text}\n\n---\n（用户消息中的 ${names} 是已加载的技能，对应指令如下，完成用户需求时请遵循。）\n${blocks.join('\n\n')}`;
}

/** 单个技能的注入块：目录式带资源目录与文件清单 */
async function buildSkillBlock(skill: SkillEntry): Promise<string> {
  if (skill.dir == null) {
    return skill.body
      ? `【技能 @${skill.name}】\n${skill.body}`
      : `【技能 @${skill.name}】（技能文件没有正文，按用户消息直接执行）`;
  }
  const listing = await listSkillDir(skill.dir);
  const lines = [
    `【技能 @${skill.name}】`,
    `技能资源目录：${skill.dir}${listing ? `（目录内文件：${listing}）` : '（目录内没有其他文件）'}`,
    '目录内的脚本/模板等资源按需使用：命令执行用绝对路径，读取文件内容用 read 工具；不要改动或删除其中的文件。',
  ];
  if (skill.body) lines.push(skill.body);
  return lines.join('\n');
}

/** 技能目录的一层文件清单（目录带 / 后缀，排除 SKILL.md 自身）；
 *  超过 20 项截断。目录不可读返回空串。 */
async function listSkillDir(dir: string): Promise<string> {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    const names = entries
      .filter(e => e.name !== 'SKILL.md')
      .map(e => (e.isDirectory() ? `${e.name}/` : e.name));
    return names.length > 20 ? `${names.slice(0, 20).join('、')}…` : names.join('、');
  } catch { return ''; }
}
