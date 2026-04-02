import { copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const rootDir = process.cwd();
const buildWebDir = path.join(rootDir, 'build', 'web');

await mkdir(buildWebDir, { recursive: true });

for (const fileName of ['privacy.html', 'delete-account.html']) {
  await copyFile(path.join(rootDir, fileName), path.join(buildWebDir, fileName));
}

console.log('Web hosting assets prepared in build/web.');
