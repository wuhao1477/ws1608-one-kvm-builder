#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const [, , outputDirectory, rootfsUuid, buildRevision] = process.argv;
if (!outputDirectory || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(rootfsUuid ?? '')) {
  throw new Error('a safe output directory and rootfs UUID are required');
}
if (!/^b[0-9]{6}$/.test(buildRevision ?? '')) throw new Error('build revision must be bRRRAAA');
if (fs.existsSync(outputDirectory) && fs.lstatSync(outputDirectory).isSymbolicLink()) {
  throw new Error('output directory must not be a symlink');
}
fs.mkdirSync(outputDirectory, { recursive: true });

const console = 'console=tty1 console=ttyAML0,115200n8 no_console_suspend consoleblank=0';
const bootCommand = `# WS1608 recovery-first Linux 3.10 trial ${buildRevision}
if test -n "\${bootdev}"; test $? != 0; then
  echo "bootdev is required"
  exit 22
fi

fatload \${bootdev} 0x20800000 /armbianEnv.txt && env import -t 0x20800000 \${filesize}
if test -n "\${rootdev}"; test $? != 0; then
  echo "rootdev is required"
  exit 22
fi

setenv boot_recovery 'setenv bootargs root=\${rootdev} rootfstype=ext4 rootwait rw ${console}; fatload \${bootdev} 0x20800000 /uImage.recovery; fatload \${bootdev} 0x22000000 /uInitrd.recovery; fatload \${bootdev} 0x21800000 /dtb/meson8b-onecloud.recovery.dtb; bootm 0x20800000 0x22000000 0x21800000'
setenv boot_amlenc 'setenv bootargs root=\${rootdev} rootfstype=ext4 rootwait rw ${console} panic=10 loglevel=8 ignore_loglevel; fatload \${bootdev} 0x20800000 /uImage.amlenc; fatload \${bootdev} 0x21800000 /dtb/meson8b-onecloud-amlenc.dtb; bootm 0x20800000 - 0x21800000'

if fatload \${bootdev} 0x13000000 /amlenc-force-recovery; then
  run boot_recovery
  exit 1
fi
if fatload \${bootdev} 0x13000000 /amlenc-legacy-trial-armed; then
  run boot_amlenc
  exit 1
fi
if fatload \${bootdev} 0x13000000 /amlenc-3.10.ok; then
  run boot_amlenc
  exit 1
fi
if test "\${amlenc_trial_revision}" = "${buildRevision}"; then
  run boot_recovery
  exit 1
fi

setenv amlenc_trial_revision ${buildRevision}
if saveenv; then
  run boot_amlenc
else
  echo "saveenv failed; booting recovery"
  run boot_recovery
fi
exit 1
`;

const environment = `console=both
rootdev=UUID=${rootfsUuid}
rootfstype=ext4
build_revision=${buildRevision}
`;

fs.writeFileSync(path.join(outputDirectory, 'boot.cmd'), bootCommand);
fs.writeFileSync(path.join(outputDirectory, 'armbianEnv.txt'), environment);
fs.writeFileSync(path.join(outputDirectory, 'amlenc-force-recovery'), 'recovery-first\n');
