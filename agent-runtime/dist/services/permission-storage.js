import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
const permissionFile = join(homedir(), '.orbby', 'setting', 'permission.js');
export function loadPermissionMode() {
    try {
        const value = JSON.parse(readFileSync(permissionFile, 'utf8'));
        return value.mode === 'all' || value.mode === 'read' || value.mode === 'ask'
            ? value.mode
            : 'ask';
    }
    catch {
        return 'ask';
    }
}
export function savePermissionMode(mode) {
    const directory = join(homedir(), '.orbby', 'setting');
    mkdirSync(directory, { recursive: true });
    writeFileSync(permissionFile, `${JSON.stringify({ mode }, null, 2)}\n`, 'utf8');
}
