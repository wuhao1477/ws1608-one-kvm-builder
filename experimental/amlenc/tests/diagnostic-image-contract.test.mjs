import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const builder = 'experimental/amlenc/scripts/build-diagnostic-image.sh';
const bootRenderer = 'experimental/amlenc/scripts/render-diagnostic-boot.mjs';
const rootfsConfigurator = 'experimental/amlenc/scripts/configure-diagnostic-rootfs.sh';
const portableInstaller = 'experimental/amlenc/scripts/install-file.sh';
const packageManifestWriter = 'experimental/amlenc/scripts/write-package-manifest.sh';
const rootfsArchiver = 'experimental/amlenc/scripts/archive-rootfs.sh';
const aptInstaller = 'experimental/amlenc/scripts/apt-install.sh';
const modeVerifier = 'experimental/amlenc/scripts/verify-debugfs-mode.sh';

function copyFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-diag-image-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const group of ['kernel', 'libvpcodec']) {
    const source = path.resolve('out/amlenc', group);
    const target = path.join(root, group);
    fs.cpSync(source, target, { recursive: true });
  }
  return root;
}

function audit(inputRoot, outputDir) {
  return spawnSync('bash', [builder, '--audit-inputs'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      AMLENC_KERNEL_OUTPUT_DIR: path.join(inputRoot, 'kernel'),
      AMLENC_LIBVPCODEC_OUTPUT_DIR: path.join(inputRoot, 'libvpcodec'),
      AMLENC_DIAGNOSTIC_IMAGE_OUTPUT_DIR: outputDir,
      AMLENC_BUILD_REVISION: 'local001',
    },
    encoding: 'utf8',
  });
}

test('audits immutable diagnostic image inputs and writes an untested manifest', (t) => {
  assert.equal(fs.existsSync(builder), true, `${builder} must exist`);
  const inputRoot = copyFixture(t);
  const outputDir = path.join(inputRoot, 'output');

  const result = audit(inputRoot, outputDir);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const manifest = JSON.parse(fs.readFileSync(path.join(outputDir, 'input-manifest.json')));
  assert.equal(manifest.schema, 1);
  assert.equal(manifest.kind, 'ws1608-amlenc-diagnostic-usb-image');
  assert.equal(manifest.kernel.version, '3.10.107');
  assert.equal(manifest.kernel.commit, '5aed95d35d252cafc75ce613a3a0052285662de2');
  assert.equal(manifest.encoder.abi, 1);
  assert.equal(manifest.encoder.commit, 'bfee62dad4f7ebb6d1705df8522da871dcad861e');
  assert.equal(manifest.encoder.redistribution, 'local-test-only');
  assert.equal(manifest.userspace, 'debian-bullseye-armhf');
  assert.equal(manifest.hardware_encoder_tested, false);
  assert.equal(manifest.one_kvm_included, false);
  assert.equal(manifest.stable_channel_modified, false);
  assert.equal(manifest.build_revision, 'local001');
  assert.match(manifest.image_name, /^WS1608-AMLENC-Diagnostic_k3\.10\.107_bullseye_local001\.usb\.img$/);
  assert.deepEqual(manifest.partition_layout, {
    boot_start_mib: 16,
    boot_size_mib: 256,
    rootfs_start_mib: 272,
    rootfs_size_bytes: 1400897536,
  });
  for (const digest of Object.values(manifest.inputs)) {
    assert.match(digest, /^[a-f0-9]{64}$/);
  }
});

test('rejects a modified kernel artifact before image assembly', (t) => {
  const inputRoot = copyFixture(t);
  fs.appendFileSync(path.join(inputRoot, 'kernel', 'zImage'), 'modified');

  const result = audit(inputRoot, path.join(inputRoot, 'output'));

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /kernel.*checksum|checksum.*kernel/i);
});

test('rejects a modified local-only encoder artifact before image assembly', (t) => {
  const inputRoot = copyFixture(t);
  fs.appendFileSync(path.join(inputRoot, 'libvpcodec', 'libvpcodec.so'), 'modified');

  const result = audit(inputRoot, path.join(inputRoot, 'output'));

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /encoder.*checksum|checksum.*encoder/i);
});

test('refuses an unsafe or nonempty output directory', (t) => {
  const inputRoot = copyFixture(t);
  const outputDir = path.join(inputRoot, 'output');
  fs.mkdirSync(outputDir);
  fs.writeFileSync(path.join(outputDir, 'old-result'), 'stale');

  const result = audit(inputRoot, outputDir);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /output directory.*empty/i);
});

test('installs a rootfs asset when its destination parents do not exist', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-install-file-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const source = path.join(directory, 'source');
  const destination = path.join(directory, 'rootfs/usr/local/libexec/ws1608-amlenc/tool');
  fs.writeFileSync(source, 'diagnostic-tool\n', { mode: 0o644 });

  const result = spawnSync('bash', [portableInstaller, '0755', source, destination], {
    cwd: process.cwd(), encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'diagnostic-tool\n');
  assert.equal(fs.statSync(destination).mode & 0o777, 0o755);
});

test('writes a sorted package manifest using an unexpanded dpkg format', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-package-manifest-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const command = path.join(directory, 'dpkg-query');
  const argumentLog = path.join(directory, 'argument');
  const output = path.join(directory, 'packages.txt');
  fs.writeFileSync(command, `#!/bin/sh\nprintf '%s\\n' "$2" >"${argumentLog}"\nprintf 'zlib 1.2 armhf\\nlibc6 2.31 armhf\\n'\n`, { mode: 0o755 });

  const result = spawnSync('bash', [packageManifestWriter, output], {
    cwd: process.cwd(), env: { ...process.env, PATH: `${directory}:${process.env.PATH}` }, encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(argumentLog, 'utf8'), '-f=${Package} ${Version} ${Architecture}\\n\n');
  assert.equal(fs.readFileSync(output, 'utf8'), 'libc6 2.31 armhf\nzlib 1.2 armhf\n');
});

test('archives the rootfs without host repository or build mounts', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-rootfs-archive-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const rootfs = path.join(directory, 'rootfs');
  const archive = path.join(directory, 'rootfs.tar');
  fs.mkdirSync(path.join(rootfs, 'etc'), { recursive: true });
  fs.mkdirSync(path.join(rootfs, 'repo'), { recursive: true });
  fs.mkdirSync(path.join(rootfs, 'work'), { recursive: true });
  fs.mkdirSync(path.join(rootfs, 'build-tools'), { recursive: true });
  fs.writeFileSync(path.join(rootfs, 'etc/issue'), 'Debian GNU/Linux 11\n');
  fs.writeFileSync(path.join(rootfs, 'repo/host-secret'), 'must not be archived\n');
  fs.writeFileSync(path.join(rootfs, 'work/build-state'), 'must not be archived\n');
  fs.writeFileSync(path.join(rootfs, 'build-tools/apt-install'), 'must not be archived\n');

  const result = spawnSync('bash', [rootfsArchiver, archive, rootfs], {
    cwd: process.cwd(), encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const listing = spawnSync('tar', ['-tf', archive], { encoding: 'utf8' });
  assert.equal(listing.status, 0, listing.stderr);
  assert.match(listing.stdout, /(?:^|\n)\.\/etc\/issue\n/);
  assert.doesNotMatch(listing.stdout, /(?:^|\n)\.\/(?:repo|work|build-tools)\//);
});

test('configures APT retries for metadata and package downloads', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-apt-install-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const command = path.join(directory, 'apt-get');
  const log = path.join(directory, 'calls');
  fs.writeFileSync(command, `#!/bin/sh\nprintf '%s\\n' "$*" >>"${log}"\ncase "$*" in *'-o Acquire::Retries=5'*) exit 0;; *) exit 1;; esac\n`, { mode: 0o755 });

  const result = spawnSync('bash', [aptInstaller, 'jq', 'e2fsprogs'], {
    cwd: process.cwd(), env: { ...process.env, PATH: `${directory}:${process.env.PATH}` }, encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(log, 'utf8'), [
    '-o Acquire::Retries=5 update',
    '-o Acquire::Retries=5 install -y --no-install-recommends jq e2fsprogs',
    '',
  ].join('\n'));
});

test('accepts debugfs permission output without a file-type prefix', () => {
  const result = spawnSync('bash', [modeVerifier, '0755'], {
    cwd: process.cwd(), input: 'Inode: 4383   Type: regular    Mode:  0755   Flags: 0x80000\n', encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);

  const wrongMode = spawnSync('bash', [modeVerifier, '0755'], {
    cwd: process.cwd(), input: 'Inode: 4383   Type: regular    Mode:  0644   Flags: 0x80000\n', encoding: 'utf8',
  });
  assert.notEqual(wrongMode.status, 0);
});

test('renders a no-initrd legacy boot flow for the diagnostic rootfs', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-boot-config-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const uuid = '11111111-2222-3333-4444-555555555555';

  const result = spawnSync(process.execPath, [bootRenderer, directory, uuid], {
    cwd: process.cwd(), encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const command = fs.readFileSync(path.join(directory, 'boot.cmd'), 'utf8');
  const environment = fs.readFileSync(path.join(directory, 'amlencEnv.txt'), 'utf8');
  assert.match(command, /fatload \$\{bootdev\} 0x20800000 \/uImage/);
  assert.match(command, /fatload \$\{bootdev\} 0x21800000 \/ws1608-s805\.dtb/);
  assert.match(command, /bootm 0x20800000 - 0x21800000/);
  assert.doesNotMatch(command, /uInitrd|0x22000000/);
  assert.match(command, /root=\$\{rootdev\} rootfstype=ext4 rootwait rw/);
  assert.match(environment, new RegExp(`^rootdev=UUID=${uuid}$`, 'm'));
  assert.match(environment, /^console=both$/m);
  assert.match(environment, /^extraargs=panic=10$/m);
});

test('configures a passwordless diagnostic rootfs with DHCP and first-boot SSH keys', (t) => {
  const rootfs = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-rootfs-layout-'));
  t.after(() => fs.rmSync(rootfs, { recursive: true, force: true }));
  const publicKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyKey ws1608-test';

  const result = spawnSync('bash', [rootfsConfigurator, rootfs], {
    cwd: process.cwd(),
    env: { ...process.env, AMLENC_SSH_PUBLIC_KEY: publicKey },
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(path.join(rootfs, 'root/.ssh/authorized_keys'), 'utf8'), `${publicKey}\n`);
  assert.match(fs.readFileSync(path.join(rootfs, 'etc/ssh/sshd_config.d/ws1608-amlenc.conf'), 'utf8'), /PasswordAuthentication no/);
  assert.match(fs.readFileSync(path.join(rootfs, 'etc/ssh/sshd_config.d/ws1608-amlenc.conf'), 'utf8'), /PermitRootLogin prohibit-password/);
  assert.match(fs.readFileSync(path.join(rootfs, 'etc/network/interfaces'), 'utf8'), /iface eth0 inet dhcp/);
  assert.match(fs.readFileSync(path.join(rootfs, 'etc/init.d/ws1608-amlenc-firstboot'), 'utf8'), /ssh-keygen -A/);
  const probePath = path.join(rootfs, 'usr/local/sbin/ws1608-amlenc-probe');
  const firstBootPath = path.join(rootfs, 'etc/init.d/ws1608-amlenc-firstboot');
  const probe = fs.readFileSync(probePath, 'utf8');
  assert.match(probe, /1280x720-8h/);
  assert.match(probe, /AMLENC_HARDWARE_LIMITS=\/usr\/local\/share\/ws1608-amlenc\/hardware-limits\.json/);
  for (const script of [probePath, firstBootPath]) {
    const syntax = spawnSync('dash', ['-n', script], { encoding: 'utf8' });
    assert.equal(syntax.status, 0, syntax.stderr);
  }
  const firstBootLink = path.join(rootfs, 'etc/rcS.d/S99ws1608-amlenc-firstboot');
  assert.equal(fs.lstatSync(firstBootLink).isSymbolicLink(), true);
  assert.equal(fs.readlinkSync(firstBootLink), '../init.d/ws1608-amlenc-firstboot');
});
