import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const verifier = 'experimental/amlenc/scripts/verify-legacy-bringup-image.sh';
const bash = fs.existsSync('/opt/homebrew/bin/bash') ? '/opt/homebrew/bin/bash' : 'bash';

function executable(filePath, content) {
  fs.writeFileSync(filePath, content, { mode: 0o755 });
}

function fixture(t, order) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-ssh-order-'));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  executable(path.join(bin, 'node'), '#!/bin/sh\ncp "$2" "$3"\n');
  executable(path.join(bin, 'e2fsck'), '#!/bin/sh\nexit 0\n');
  executable(path.join(bin, 'realpath'), '#!/bin/sh\n[ "$1" = -m ] && shift\nprintf "%s\\n" "$1"\n');
  executable(path.join(bin, 'dumpe2fs'), '#!/bin/sh\necho "Filesystem features: ext_attr"\n');
  executable(path.join(bin, 'mkimage'), '#!/bin/sh\ncase "$2" in *uImage.amlenc*) echo Linux-3.10.107-WS1608-AMLENC ;; *boot.scr*) echo WS1608-AMLENC-Bringup ;; esac\n');
  executable(path.join(bin, 'mcopy'), '#!/usr/bin/env bash\ndest="${@: -1}"\nprintf "x\\n" >"$dest"\ncase "$dest" in *uImage|*uImage.recovery|*uInitrd|*uInitrd.recovery|*meson8b-onecloud.dtb|*meson8b-onecloud.recovery.dtb) printf "recovery\\n" >"$dest" ;; *amlenc-force-recovery) printf "recovery-first" >"$dest" ;; *boot.cmd) printf "amlenc-force-recovery\\namlenc-3.10.ok\\namlenc_trial_revision\\n" >"$dest" ;; esac\n');
  executable(path.join(bin, 'debugfs'), [
    '#!/bin/sh',
    'command=$2',
    'case "$command" in',
    '  "cat /root/.ssh/authorized_keys") echo "ssh-ed25519 AAAA test" ;;',
    '  "cat /etc/ssh/sshd_config.d/ws1608-amlenc.conf") printf "PasswordAuthentication yes\\nKbdInteractiveAuthentication yes\\nPubkeyAuthentication yes\\nPermitRootLogin yes\\n" ;;',
    '  "cat /etc/shadow") echo "root:$6$test$hash:20000:0:99999:7:::" ;;',
    '  "cat /etc/fstab") echo "LABEL=armbi_boot /boot vfat defaults 0 2" ;;',
    '  "ls -p /etc/ssh") echo "/42/100644/0/0/sshd_config/1/" ;;',
    '  "ls -p /etc/rc2.d"|"ls -p /etc/rc3.d"|"ls -p /etc/rc4.d"|"ls -p /etc/rc5.d") if [ "$LEGACY_TEST_RC_ORDER" = reversed ]; then printf "/42/120777/0/0/S03ws1608-amlenc-firstboot/40/\\n/43/120777/0/0/S02ssh/20/\\n"; else printf "/42/120777/0/0/S01ws1608-amlenc-firstboot/40/\\n/43/120777/0/0/S02ssh/20/\\n"; fi ;;',
    '  "stat /etc/rc"*"/S"*"ws1608-amlenc-firstboot") echo "Inode: 42 Type: symlink"; echo "Fast link dest: \\"../init.d/ws1608-amlenc-firstboot\\"" ;;',
    '  "stat /etc/init.d/ws1608-amlenc-firstboot"|"stat /usr/local/sbin/ws1608-amlenc-"*) echo "Inode: 42 Mode:  0755" ;;',
    '  "stat /usr/bin/one-kvm"|"stat /etc/rcS.d/"*) exit 1 ;;',
    '  "stat /var/lib/ws1608-amlenc/firstboot-complete"|"stat /tmp/ws1608-amlenc-firstboot.complete") exit 1 ;;',
    '  stat*) echo "Inode: 42 Mode: 0644" ;;',
    'esac',
  ].join('\n'));
  const amlimg = path.join(root, 'AmlImg');
  executable(amlimg, [
    '#!/bin/sh', 'out=$3', 'mkdir -p "$out"',
    'printf "PARTITION:boot:x:boot.PARTITION\\nVERIFY:boot:x:boot.VERIFY\\nPARTITION:rootfs:x:rootfs.PARTITION\\nVERIFY:rootfs:x:rootfs.VERIFY\\nPARTITION:bootloader:x:bootloader.PARTITION\\nVERIFY:bootloader:x:bootloader.VERIFY\\nPARTITION:resource:x:resource.PARTITION\\nVERIFY:resource:x:resource.VERIFY\\n" >"$out/commands.txt"',
    'for name in boot rootfs bootloader resource; do if [ "$name" = bootloader ] || [ "$name" = resource ]; then prefix=shared; elif [ "$(basename "$2")" = base.img ]; then prefix=base; else prefix=final; fi; printf "%s-%s\\n" "$prefix" "$name" >"$out/$name.PARTITION"; printf "sha1sum %s" "$(sha1sum "$out/$name.PARTITION" | awk "{print \\$1}")" >"$out/$name.VERIFY"; done',
  ].join('\n'));
  const image = path.join(root, 'final.img');
  const base = path.join(root, 'base.img');
  const manifest = path.join(root, 'manifest.json');
  fs.writeFileSync(image, 'final\n');
  fs.writeFileSync(base, 'base\n');
  fs.writeFileSync(manifest, JSON.stringify({
    schema: 1, kind: 'ws1608-amlenc-legacy-bringup', image_sha256: 'x',
    recovery: { kernel: '6.12.28-current-meson', source: 'stable-base' },
    legacy: { kernel: '3.10.107', commit: '5aed95d35d252cafc75ce613a3a0052285662de2', cma_mib: 64 },
    partitions: {}, ssh_public_key_sha256: 'x', default_login_user: 'root', password_authentication: true,
    recovery_first: true, hardware_boot_tested: false, hardware_encoder_tested: false,
    one_kvm_included: false, hid_tested: false, msd_tested: false, stable_channel_modified: false,
  }));
  return { root, bin, image, base, manifest, amlimg, order };
}

test('rejects a legacy image when firstboot runs after SSH', (t) => {
  const setup = fixture(t, 'reversed');
  const result = spawnSync(bash, [verifier], {
    env: { ...process.env, PATH: `${setup.bin}:${process.env.PATH}`, IMAGE: setup.image, BASE_IMAGE: setup.base,
      MANIFEST: setup.manifest, AMLIMG_BIN: setup.amlimg, VERIFY_DIR: path.join(setup.root, 'verify'),
      LEGACY_TEST_RC_ORDER: setup.order }, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /firstboot must precede ssh/i);
});
