import fs from 'node:fs';

import { validateBootConsole } from './lib/boot-console.mjs';

const [envPath, bootCmdPath] = process.argv.slice(2);
if (!envPath || !bootCmdPath) {
  throw new Error('armbianEnv.txt and boot.cmd paths are required');
}

const args = validateBootConsole(
  fs.readFileSync(envPath, 'utf8'),
  fs.readFileSync(bootCmdPath, 'utf8'),
);
process.stdout.write(`validated boot console args: ${args.join(' ')}\n`);
