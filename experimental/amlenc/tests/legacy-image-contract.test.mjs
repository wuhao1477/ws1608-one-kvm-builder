import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const files = {
  config: 'experimental/amlenc/config/legacy-bringup.env',
  rootfs: 'experimental/amlenc/scripts/build-legacy-rootfs.sh',
  image: 'experimental/amlenc/scripts/build-legacy-bringup-image.sh',
  verify: 'experimental/amlenc/scripts/verify-legacy-bringup-image.sh',
};
const bash = fs.existsSync('/opt/homebrew/bin/bash') ? '/opt/homebrew/bin/bash' : 'bash';

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

function envValue(filePath, name) {
  const match = readRequired(filePath).match(new RegExp(`^${name}=(.+)$`, 'm'));
  assert.notEqual(match, null, `${name} must exist`);
  return match[1];
}

function sha256Text(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function sha256Identity(line) {
  return sha256Text(`${line}\n`);
}

function writeExecutable(filePath, content) {
  fs.writeFileSync(filePath, content, { mode: 0o755 });
}

function installVerifierStubs(directory) {
  writeExecutable(path.join(directory, 'node'), '#!/bin/sh\ncp "$2" "$3"\n');
  writeExecutable(path.join(directory, 'e2fsck'), '#!/bin/sh\nexit 0\n');
  writeExecutable(path.join(directory, 'realpath'), '#!/bin/sh\n[ "$1" = -m ] && shift\nprintf "%s\\n" "$1"\n');
  writeExecutable(path.join(directory, 'dumpe2fs'), [
    '#!/bin/sh',
    'echo "Filesystem features: has_journal ext_attr resize_inode dir_index filetype needs_recovery extent flex_bg sparse_super large_file huge_file uninit_bg dir_nlink extra_isize"',
  ].join('\n'));
  writeExecutable(path.join(directory, 'mkimage'), [
    '#!/bin/sh',
    'case "$2" in',
    '  *uImage.amlenc*) echo "Image Name: Linux-3.10.107-WS1608-AMLENC" ;;',
    '  *boot.scr*) echo "Image Name: WS1608-AMLENC-Bringup" ;;',
    'esac',
  ].join('\n'));
  writeExecutable(path.join(directory, 'mcopy'), [
    '#!/usr/bin/env bash',
    'set -eu',
    'dest="${@: -1}"',
    'case "$dest" in',
    '  *uImage|*uImage.recovery) printf "recovery-kernel\\n" >"$dest" ;;',
    '  *uInitrd|*uInitrd.recovery) printf "recovery-initrd\\n" >"$dest" ;;',
    '  *meson8b-onecloud.dtb|*meson8b-onecloud.recovery.dtb) printf "recovery-dtb\\n" >"$dest" ;;',
    '  *uImage.amlenc) printf "legacy-kernel\\n" >"$dest" ;;',
    '  *boot.cmd) printf "amlenc-force-recovery\\namlenc-3.10.ok\\namlenc_trial_revision\\n" >"$dest" ;;',
    '  *boot.scr) printf "boot-script\\n" >"$dest" ;;',
    '  *armbianEnv.txt) printf "env\\n" >"$dest" ;;',
    '  *amlenc-force-recovery) printf "recovery-first" >"$dest" ;;',
    '  *) printf "copied\\n" >"$dest" ;;',
    'esac',
  ].join('\n'));
  writeExecutable(path.join(directory, 'debugfs'), [
    '#!/usr/bin/env bash',
    'set -eu',
    'command=$2',
    'case "$command" in',
    '  "cat /root/.ssh/authorized_keys") printf "%s\\n" "$LEGACY_TEST_AUTHORIZED_KEYS" ;;',
    '  "cat /etc/ssh/sshd_config.d/ws1608-amlenc.conf") printf "PasswordAuthentication yes\\nKbdInteractiveAuthentication yes\\nPubkeyAuthentication yes\\nPermitRootLogin yes\\n" ;;',
    '  "cat /etc/shadow") printf "root:\\$6\\$test\\$hash:20000:0:99999:7:::\\n" ;;',
    '  "cat /etc/fstab") printf "LABEL=armbi_boot /boot vfat defaults 0 2\\n" ;;',
    '  "ls -p /etc/ssh") if [ "$LEGACY_TEST_FORBIDDEN" = host-key ]; then echo "/42/100600/0/0/ssh_host_test_key/16/"; else echo "/42/100644/0/0/sshd_config/3289/"; fi ;;',
    '  "stat /usr/bin/one-kvm") exit 1 ;;',
    '  "ls -p /etc/rc2.d"|"ls -p /etc/rc3.d"|"ls -p /etc/rc4.d"|"ls -p /etc/rc5.d") if [ "$LEGACY_TEST_RC_ORDER" = reversed ]; then printf "/42/120777/0/0/S03ws1608-amlenc-firstboot/40/\\n/43/120777/0/0/S02ssh/20/\\n"; else printf "/42/120777/0/0/S01ws1608-amlenc-firstboot/40/\\n/43/120777/0/0/S02ssh/20/\\n"; fi ;;',
    '  "stat /etc/rcS.d/S99ws1608-amlenc-firstboot"|"stat /etc/rcS.d/S01ws1608-amlenc-firstboot"|"stat /etc/ssh/ssh_host_"*|"stat /boot/amlenc-legacy-firstboot-"*|"stat /boot/amlenc-legacy-trial-armed"|"stat /boot/amlenc-legacy-dmesg.log"|"stat /var/lib/ws1608-amlenc/firstboot-complete") exit 1 ;;',
    '  "stat /etc/rc"*"/S01ws1608-amlenc-firstboot") echo "Inode: 42   Type: symlink    Mode:  0777"; echo "Fast link dest: \\"../init.d/ws1608-amlenc-firstboot\\"" ;;',
    '  "stat /tmp/ws1608-amlenc-firstboot.complete") if [ "$LEGACY_TEST_FORBIDDEN" = build-marker ]; then echo "Inode: 42   Type: regular    Mode:  0644"; fi ;;',
    '  "stat /etc/init.d/ws1608-amlenc-firstboot") echo "Inode: 42   Type: regular    Mode:  0755" ;;',
    '  "stat /usr/local/sbin/ws1608-amlenc-probe"|"stat /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag"|"stat /usr/local/libexec/ws1608-amlenc/validate-h264.sh") echo "Inode: 42   Type: regular    Mode:  0755" ;;',
    '  "stat /usr/local/lib/ws1608-amlenc/libvpcodec.so"|"stat /usr/local/share/ws1608-amlenc/frame-"*) echo "Inode: 42   Type: regular    Mode:  0644" ;;',
    '  "stat /usr/local/share/ws1608-amlenc/hardware-limits.json") echo "Inode: 42   Type: regular    Mode:  0644" ;;',
    '  "stat /usr/local/sbin/ws1608-amlenc-"*) echo "Inode: 42   Type: regular    Mode:  0755" ;;',
    '  stat*) echo "Inode: 42   Type: regular    Mode:  0644" ;;',
    'esac',
  ].join('\n'));
}

function writeAmlImgStub(filePath) {
  writeExecutable(filePath, [
    '#!/usr/bin/env bash',
    'set -eu',
    'out=$3',
    'mkdir -p "$out"',
    'cat >"$out/commands.txt" <<EOF',
    'PARTITION:boot:normal:boot.PARTITION',
    'VERIFY:boot:normal:boot.VERIFY',
    'PARTITION:rootfs:normal:rootfs.PARTITION',
    'VERIFY:rootfs:normal:rootfs.VERIFY',
    'PARTITION:bootloader:normal:bootloader.PARTITION',
    'VERIFY:bootloader:normal:bootloader.VERIFY',
    'PARTITION:resource:normal:resource.PARTITION',
    'VERIFY:resource:normal:resource.VERIFY',
    'EOF',
    'case "$(basename "$2")" in *base*) prefix=base ;; *) prefix=final ;; esac',
    'for name in boot rootfs bootloader resource; do',
    '  if [ "$name" = bootloader ] || [ "$name" = resource ]; then content=shared-$name; else content=$prefix-$name; fi',
    '  printf "%s\\n" "$content" >"$out/$name.PARTITION"',
    '  printf "sha1sum %s" "$(sha1sum "$out/$name.PARTITION" | awk \'{print $1}\')" >"$out/$name.VERIFY"',
    'done',
  ].join('\n'));
}

function runLegacyVerifier(t, manifestKeySha256, authorizedKey, forbidden = '', rcOrder = '') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-legacy-verify-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  installVerifierStubs(bin);
  const amlImg = path.join(root, 'AmlImg');
  writeAmlImgStub(amlImg);
  const image = path.join(root, 'final.img');
  const baseImage = path.join(root, 'base.img');
  const manifest = path.join(root, 'manifest.json');
  fs.writeFileSync(image, 'final image\n');
  fs.writeFileSync(baseImage, 'base image\n');
  fs.writeFileSync(manifest, JSON.stringify({
    schema: 1,
    kind: 'ws1608-amlenc-legacy-bringup',
    image_sha256: sha256Text('final image\n'),
    base_release_tag: envValue('config/base.env', 'BASE_RELEASE_TAG'),
    base_image_sha256: envValue('config/base.env', 'BASE_IMAGE_SHA256'),
    recovery: { kernel: '6.12.28-current-meson', source: 'stable-base' },
    legacy: { kernel: '3.10.107', commit: envValue('experimental/amlenc/config/sources.env', 'LINUX_COMMIT'), cma_mib: 64 },
    partitions: {
      boot_sha256: sha256Text('final-boot\n'),
      rootfs_sha256: sha256Text('final-rootfs\n'),
    },
    ssh_public_key_sha256: manifestKeySha256,
    default_login_user: 'root',
    password_authentication: true,
    recovery_first: true,
    hardware_boot_tested: false,
    hardware_encoder_tested: false,
    one_kvm_included: false,
    hid_tested: false,
    msd_tested: false,
    stable_channel_modified: false,
  }) + '\n');

  return spawnSync(bash, [files.verify], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      IMAGE: image,
      MANIFEST: manifest,
      BASE_IMAGE: baseImage,
      AMLIMG_BIN: amlImg,
      VERIFY_DIR: path.join(root, 'verify'),
      LEGACY_TEST_AUTHORIZED_KEYS: authorizedKey,
      LEGACY_TEST_FORBIDDEN: forbidden,
      LEGACY_TEST_RC_ORDER: rcOrder,
    },
    encoding: 'utf8',
  });
}

test('defines fixed legacy bring-up partition and kernel identities', () => {
  const config = readRequired(files.config);
  assert.match(config, /^LEGACY_ROOTFS_UUID=7c59bb76-d17e-4a9c-9ff8-031b35133010$/m);
  assert.match(config, /^LEGACY_ROOTFS_BYTES=1400897536$/m);
  assert.match(config, /^LEGACY_BOOT_BYTES=268435456$/m);
  assert.match(config, /^RECOVERY_KERNEL=6\.12\.28-current-meson$/m);
  assert.match(config, /^LEGACY_KERNEL=3\.10\.107$/m);
  assert.match(config, /^RECOVERY_BOOT_LABEL=armbi_boot$/m);
});

test('rejects a legacy image when the root SSH key does not match the manifest identity', (t) => {
  const key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyKey ws1608-test';
  const result = runLegacyVerifier(t, sha256Identity(`${key} changed`), key);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ssh.*key|key.*ssh/i);
});

test('requires the default root password login contract', () => {
  const config = readRequired(files.config);
  const rootfs = readRequired(files.rootfs);
  assert.match(config, /^LEGACY_DEFAULT_LOGIN_USER=root$/m);
  assert.match(config, /^LEGACY_DEFAULT_LOGIN_PASSWORD=ws1608$/m);
  assert.match(rootfs, /LEGACY_DEFAULT_LOGIN_PASSWORD/);
  assert.match(rootfs, /chpasswd/);
  assert.doesNotMatch(rootfs, /passwd -l root/);
  assert.match(rootfs, /PasswordAuthentication yes/);
  assert.match(rootfs, /KbdInteractiveAuthentication yes/);
  assert.match(rootfs, /PermitRootLogin yes/);
});

test('rejects preinstalled host keys and build-time firstboot markers', (t) => {
  const key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyKey ws1608-test';
  for (const forbidden of ['host-key', 'build-marker']) {
    const result = runLegacyVerifier(t, sha256Identity(key), key, forbidden);
    assert.notEqual(result.status, 0, forbidden + ' must be rejected');
    assert.match(result.stderr, /host key|firstboot|forbidden/i);
  }
});

test('independently verifies recovery identity, rootfs and untested status', () => {
  const verify = readRequired(files.verify);
  assert.match(verify, /AmlImg|AMLIMG_BIN/);
  assert.match(verify, /cmp[\s\S]*base[\s\S]*final/);
  assert.match(verify, /name.*!=.*boot.*name.*!=.*rootfs/);
  assert.match(verify, /sha1sum/);
  assert.match(verify, /e2fsck/);
  assert.match(verify, /mcopy/);
  assert.match(verify, /mkimage -l/);
  assert.match(verify, /debugfs/);
  assert.match(verify, /uImage\.recovery/);
  assert.match(verify, /uInitrd\.recovery/);
  assert.match(verify, /6\.12\.28-current-meson/);
  assert.match(verify, /3\.10\.107/);
  assert.match(verify, /ws1608-amlenc-arm-trial/);
  assert.match(verify, /ws1608-amlenc-mark-success/);
  assert.match(verify, /ls -p \/etc\/rc\$\{level\}\.d/);
  assert.match(verify, /ssh_host_\[\^\/\]\+/);
  for (const pattern of [/PasswordAuthentication yes/, /PermitRootLogin yes/, /cat \/etc\/shadow/, /root:\\\$\[\^:\]\+/]) assert.match(verify, pattern);
  assert.match(verify, /one-kvm/);
  for (const field of ['hardware_boot_tested', 'hardware_encoder_tested', 'one_kvm_included', 'hid_tested', 'msd_tested']) assert.match(verify, new RegExp(`${field}.*false`));
});

test('builds a Bullseye SysV rootfs for both kernels without One-KVM', () => {
  const rootfs = readRequired(files.rootfs);
  const offlineMountpoints = rootfs.slice(
    rootfs.indexOf('tar --numeric-owner'),
    rootfs.indexOf('debugfs -R'),
  );
  assert.match(rootfs, /BULLSEYE_ARMV7_OCI_IMAGE/);
  for (const packageName of ['sysvinit-core', 'sysv-rc', 'insserv', 'udev', 'kmod', 'ifupdown', 'isc-dhcp-client', 'openssh-server']) {
    assert.match(rootfs, new RegExp(packageName));
  }
  for (const pattern of [/LEGACY_DEFAULT_LOGIN_PASSWORD/, /chpasswd/, /PasswordAuthentication yes/, /KbdInteractiveAuthentication yes/, /PermitRootLogin yes/, /PubkeyAuthentication yes/]) assert.match(rootfs, pattern);
  assert.doesNotMatch(rootfs, /passwd -l root/);
  assert.match(rootfs, /authorized_keys/);
  assert.match(rootfs, /RECOVERY_ROOTFS_RAW/);
  assert.match(rootfs, /LEGACY_MODULES_TAR/);
  assert.match(rootfs, /lib\/modules\/6\.12\.28-current-meson/);
  assert.match(rootfs, /ws1608-amlenc-arm-trial/);
  assert.match(rootfs, /ws1608-amlenc-mark-success/);
  assert.match(rootfs, /ws1608-amlenc-firstboot/);
  for (const pattern of [/update-rc\.d ws1608-amlenc-firstboot defaults/, /update-rc\.d ssh defaults/]) assert.match(rootfs, pattern);
  assert.doesNotMatch(rootfs, /ln -s \.\.\/init\.d\/ws1608-amlenc-firstboot/);
  assert.match(rootfs, /STATUS_FILE=.*ws1608-amlenc-firstboot/);
  assert.match(rootfs, /SSHD_START_BIN=\/bin\/true/);
  assert.match(rootfs, /LABEL=armbi_boot \/boot vfat/);
  assert.match(rootfs, /proc \/proc proc/);
  assert.match(rootfs, /tmpfs \/run tmpfs/);
  assert.doesNotMatch(rootfs, /install -d \/boot \/proc \/sys/);
  for (const mountpoint of ['boot', 'proc', 'sys', 'dev', 'run']) assert.match(offlineMountpoints, new RegExp('/work/rootfs-tree/' + mountpoint));
  assert.doesNotMatch(rootfs, /one-kvm\.deb|\/usr\/bin\/one-kvm/);
});

test('creates offline rootfs mountpoints with POSIX shell semantics', (t) => {
  const rootfs = readRequired(files.rootfs);
  const start = rootfs.indexOf('mkdir -p /work/rootfs-tree/boot');
  const end = rootfs.indexOf('\n    debugfs -R', start);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-mountpoints-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const command = rootfs.slice(start, end).replaceAll('/work/rootfs-tree', directory);
  const result = spawnSync('sh', ['-c', command], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  for (const mountpoint of ['boot', 'proc', 'sys', 'dev', 'run']) assert.equal(fs.statSync(path.join(directory, mountpoint)).isDirectory(), true);
});

test('assembles dual boot and rootfs partitions inside the stable AmlImg package', () => {
  const image = readRequired(files.image);
  assert.match(image, /BASE_IMAGE_XZ/);
  assert.match(image, /AMLIMG_BIN/);
  assert.match(image, /sparse-to-raw\.mjs/);
  assert.match(image, /raw-to-sparse\.mjs/);
  assert.match(image, /build-legacy-rootfs\.sh/);
  assert.match(image, /render-legacy-trial-boot\.mjs/);
  for (const asset of [
    'uImage.recovery', 'uInitrd.recovery', 'meson8b-onecloud.recovery.dtb',
    'uImage.amlenc', 'meson8b-onecloud-amlenc.dtb', 'amlenc-force-recovery',
  ]) assert.match(image, new RegExp(asset.replaceAll('.', '\\.')));
  assert.match(image, /mkimage.*Linux-3\.10\.107-WS1608-AMLENC/s);
  assert.match(image, /sha1sum/);
  for (const pattern of [/stable_channel_modified:\s*false/, /hardware_boot_tested:\s*false/, /hardware_encoder_tested:\s*false/, /one_kvm_included:\s*false/]) assert.match(image, pattern);
  assert.doesNotMatch(image, /DIAGNOSTIC_IMAGE|DIAGNOSTIC_MANIFEST/);
});
