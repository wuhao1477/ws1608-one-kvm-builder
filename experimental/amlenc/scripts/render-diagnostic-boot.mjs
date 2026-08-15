#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const [, , outputDirectory, rootfsUuid] = process.argv;
if (!outputDirectory || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(rootfsUuid ?? '')) {
  throw new Error('usage: render-diagnostic-boot.mjs OUTPUT_DIR ROOTFS_UUID');
}
fs.mkdirSync(outputDirectory, { recursive: true });

const bootCommand = `# WS1608 AMLENC diagnostic boot
if test -n "\${bootdev}"; test $? != 0; then
  echo "bootdev is required"
  exit 22
fi

fatload \${bootdev} 0x20800000 /amlencEnv.txt && env import -t 0x20800000 \${filesize}
if test -n "\${rootdev}"; test $? != 0; then
  echo "rootdev is required"
  exit 22
fi

setenv consoleargs "console=tty1 console=ttyAML0,115200n8 no_console_suspend consoleblank=0"
setenv bootargs "root=\${rootdev} rootfstype=ext4 rootwait rw \${consoleargs} \${extraargs}"
fatload \${bootdev} 0x20800000 /uImage || exit 1
fatload \${bootdev} 0x21800000 /ws1608-s805.dtb || exit 1
bootm 0x20800000 - 0x21800000
`;
const environment = `console=both
rootdev=UUID=${rootfsUuid}
rootfstype=ext4
extraargs=panic=10
`;

fs.writeFileSync(path.join(outputDirectory, 'boot.cmd'), bootCommand);
fs.writeFileSync(path.join(outputDirectory, 'amlencEnv.txt'), environment);
