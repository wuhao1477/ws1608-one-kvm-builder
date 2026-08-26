import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const renderer = 'experimental/amlenc/scripts/render-legacy-trial-boot.mjs';
const armTrial = 'experimental/amlenc/rootfs/ws1608-amlenc-arm-trial';
const markSuccess = 'experimental/amlenc/rootfs/ws1608-amlenc-mark-success';
const firstboot = 'experimental/amlenc/rootfs/ws1608-amlenc-firstboot';
const initrd = 'experimental/amlenc/rootfs/ws1608-amlenc-initrd';
const uuid = '7c59bb76-d17e-4a9c-9ff8-031b35133010';

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-legacy-boot-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function helper(script, bootDir, overrides = {}) {
  return spawnSync('bash', [script], {
    encoding: 'utf8',
    env: {
      ...process.env,
      BOOT_DIR: bootDir,
      IP_OUTPUT: '2: eth0    inet 192.0.2.10/24 scope global eth0',
      SSHD_ACTIVE: 'true',
      ROOT_MOUNT_OPTIONS: 'rw,relatime',
      ...overrides,
    },
  });
}

function pathWithHealthyIp(t) {
  const directory = fixture(t);
  const ip = path.join(directory, 'ip');
  fs.writeFileSync(ip, '#!/bin/sh\necho "2: eth0    inet 192.0.2.10/24 scope global eth0"\n');
  fs.chmodSync(ip, 0o755);
  return `${directory}:${process.env.PATH}`;
}

function writeExecutable(filePath, content) {
  fs.writeFileSync(filePath, content, { mode: 0o755 });
}

function firstbootFixture(t, sshdExit = 0, startExit = 0) {
  const directory = fixture(t);
  const log = path.join(directory, 'commands.log');
  const hostKey = path.join(directory, 'ssh_host_test_key');
  const keygen = path.join(directory, 'ssh-keygen');
  const sshd = path.join(directory, 'sshd');
  const start = path.join(directory, 'ssh-start');
  const dmesg = path.join(directory, 'dmesg');
  fs.mkdirSync(path.join(directory, 'boot'));
  writeExecutable(keygen, [
    '#!/bin/sh',
    'printf "keygen:%s\\n" "$*" >>"$FIRSTBOOT_LOG"',
    'printf "host-key\\n" >"$FIRSTBOOT_HOST_KEY"',
  ].join('\n'));
  writeExecutable(sshd, [
    '#!/bin/sh',
    'test -s "$FIRSTBOOT_HOST_KEY"',
    'printf "sshd:%s\\n" "$*" >>"$FIRSTBOOT_LOG"',
    'exit ' + sshdExit,
  ].join('\n'));
  writeExecutable(start, [
    '#!/bin/sh',
    'printf "start:%s\\n" "$*" >>"$FIRSTBOOT_LOG"',
    'exit ' + startExit,
  ].join('\n'));
  writeExecutable(dmesg, '#!/bin/sh\nprintf "amvenc probe fixture\\n"\n');
  fs.writeFileSync(path.join(directory, 'boot', 'amlenc-legacy-trial-armed'), 'trial\n');
  return {
    log,
    env: {
      ...process.env,
      RUN_DIR: path.join(directory, 'run', 'sshd'),
      BOOT_DIR: path.join(directory, 'boot'),
      UNAME_RELEASE: '3.10.107-ws1608',
      STATUS_FILE: path.join(directory, 'state', 'firstboot-complete'),
      SSH_KEYGEN_BIN: keygen,
      SSHD_BIN: sshd,
      SSHD_START_BIN: start,
      DMESG_BIN: dmesg,
      FIRSTBOOT_LOG: log,
      FIRSTBOOT_HOST_KEY: hostKey,
    },
  };
}

test('renders a recovery-first revision-isolated boot flow', (t) => {
  assert.equal(fs.existsSync(renderer), true, 'legacy boot renderer is required');
  const output = fixture(t);
  const result = spawnSync(process.execPath, [renderer, output, uuid, 'b001001'], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const command = fs.readFileSync(path.join(output, 'boot.cmd'), 'utf8');
  const force = command.indexOf('amlenc-force-recovery');
  const armed = command.indexOf('amlenc-legacy-trial-armed');
  const button = command.indexOf('button reset');
  const success = command.indexOf('amlenc-3.10.ok');
  const attempted = command.indexOf('amlenc_trial_revision');
  assert.ok(armed >= 0 && button > armed && force > button && success > force && attempted > success);
  assert.match(command, /amlenc-legacy-trial-armed[\s\S]*button reset[\s\S]*run boot_amlenc/);
  assert.match(command, /saveenv[\s\S]*run boot_recovery/);
  assert.match(command, /uImage\.recovery/);
  assert.match(command, /uInitrd\.recovery/);
  assert.match(command, /uImage\.amlenc/);
  assert.match(command, /uInitrd\.amlenc/);
  assert.match(command, /bootm 0x20800000 0x22000000 0x21800000/);
  assert.match(command, /panic=10/);
  assert.equal(fs.readFileSync(path.join(output, 'amlenc-force-recovery'), 'utf8'), 'recovery-first\n');
  assert.match(fs.readFileSync(path.join(output, 'armbianEnv.txt'), 'utf8'), new RegExp(`rootdev=UUID=${uuid}`));
});

test('rejects unsafe renderer identities', (t) => {
  const output = fixture(t);
  for (const args of [[output, 'not-a-uuid', 'b001001'], [output, uuid, 'run-1']]) {
    const result = spawnSync(process.execPath, [renderer, ...args], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
  }
});

test('arms one legacy trial only from healthy recovery', (t) => {
  assert.equal(fs.existsSync(armTrial), true, 'trial helper is required');
  const boot = fixture(t);
  fs.writeFileSync(path.join(boot, 'amlenc-force-recovery'), 'recovery-first\n');

  const result = helper(armTrial, boot, { UNAME_RELEASE: '6.12.28-current-meson' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(path.join(boot, 'amlenc-force-recovery')), true);
  assert.match(result.stdout, /armed one Linux 3\.10\.107 trial/);
});

test('refuses to arm a trial from an unhealthy recovery', (t) => {
  const boot = fixture(t);
  const healthyIpPath = pathWithHealthyIp(t);
  for (const overrides of [
    { UNAME_RELEASE: '3.10.107' },
    { UNAME_RELEASE: '6.12.28-current-meson', IP_OUTPUT: '', PATH: healthyIpPath },
    { UNAME_RELEASE: '6.12.28-current-meson', SSHD_ACTIVE: 'false' },
    { UNAME_RELEASE: '6.12.28-current-meson', ROOT_MOUNT_OPTIONS: 'ro,relatime' },
  ]) {
    fs.writeFileSync(path.join(boot, 'amlenc-force-recovery'), 'recovery-first\n');
    const result = helper(armTrial, boot, overrides);
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(path.join(boot, 'amlenc-force-recovery')), true);
  }
});

test('marks legacy success after all stability gates pass', (t) => {
  assert.equal(fs.existsSync(markSuccess), true, 'success helper is required');
  const boot = fixture(t);

  const result = helper(markSuccess, boot, {
    UNAME_RELEASE: '3.10.107-ws1608-amlenc', UPTIME_SECONDS: '61',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(fs.readFileSync(path.join(boot, 'amlenc-3.10.ok'), 'utf8'), /3\.10\.107-ws1608-amlenc/);
});

test('refuses to mark an unstable or unhealthy legacy boot', (t) => {
  const boot = fixture(t);
  const healthyIpPath = pathWithHealthyIp(t);
  for (const overrides of [
    { UNAME_RELEASE: '6.12.28-current-meson', UPTIME_SECONDS: '61' },
    { UNAME_RELEASE: '3.10.107', UPTIME_SECONDS: '59' },
    { UNAME_RELEASE: '3.10.107', UPTIME_SECONDS: '61', IP_OUTPUT: '', PATH: healthyIpPath },
    { UNAME_RELEASE: '3.10.107', UPTIME_SECONDS: '61', SSHD_ACTIVE: 'false' },
    { UNAME_RELEASE: '3.10.107', UPTIME_SECONDS: '61', ROOT_MOUNT_OPTIONS: 'ro' },
  ]) {
    fs.rmSync(path.join(boot, 'amlenc-3.10.ok'), { force: true });
    const result = helper(markSuccess, boot, overrides);
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(path.join(boot, 'amlenc-3.10.ok')), false);
  }
});

test('generates host keys and validates sshd before marking first boot complete', (t) => {
  assert.equal(fs.existsSync(firstboot), true, 'firstboot helper is required');
  const setup = firstbootFixture(t);

  const result = spawnSync('sh', [firstboot], { encoding: 'utf8', env: setup.env });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(setup.env.STATUS_FILE, 'utf8'), 'host-keys-ready\n');
  assert.equal(fs.statSync(setup.env.RUN_DIR).mode & 0o777, 0o755);
  assert.equal(fs.readFileSync(setup.log, 'utf8'), 'keygen:-A\nsshd:-t\nstart:start\n');
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-firstboot-started')), true);
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-firstboot-ready')), true);
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-firstboot-failed')), false);
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-trial-armed')), false);
});

test('clears recovery force only after a healthy legacy userspace boot', (t) => {
  const legacy = firstbootFixture(t);
  fs.writeFileSync(path.join(legacy.env.BOOT_DIR, 'amlenc-force-recovery'), 'recovery-first\n');
  const legacyResult = spawnSync('sh', [firstboot], { encoding: 'utf8', env: legacy.env });
  assert.equal(legacyResult.status, 0, legacyResult.stderr || legacyResult.stdout);
  assert.equal(fs.existsSync(path.join(legacy.env.BOOT_DIR, 'amlenc-force-recovery')), false);

  const recovery = firstbootFixture(t);
  fs.writeFileSync(path.join(recovery.env.BOOT_DIR, 'amlenc-force-recovery'), 'recovery-first\n');
  const recoveryResult = spawnSync('sh', [firstboot], {
    encoding: 'utf8',
    env: { ...recovery.env, UNAME_RELEASE: '6.12.28-current-meson' },
  });
  assert.equal(recoveryResult.status, 0, recoveryResult.stderr || recoveryResult.stdout);
  assert.equal(fs.existsSync(path.join(recovery.env.BOOT_DIR, 'amlenc-force-recovery')), true);
});

test('does not mark first boot complete when sshd validation fails', (t) => {
  const setup = firstbootFixture(t, 42);

  const result = spawnSync('sh', [firstboot], { encoding: 'utf8', env: setup.env });

  assert.equal(result.status, 42);
  assert.equal(fs.existsSync(setup.env.STATUS_FILE), false);
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-firstboot-failed')), true);
  assert.equal(fs.existsSync(path.join(setup.env.BOOT_DIR, 'amlenc-legacy-dmesg.log')), true);
});

test('does not mark first boot complete when ssh service start fails', (t) => {
  const setup = firstbootFixture(t, 0, 42);

  const result = spawnSync('sh', [firstboot], { encoding: 'utf8', env: setup.env });

  assert.equal(result.status, 42);
  assert.equal(fs.existsSync(setup.env.STATUS_FILE), false);
});

test('declares firstboot before sshd in the SysV dependency graph', () => {
  const script = fs.readFileSync(firstboot, 'utf8');

  assert.match(script, /^# X-Start-Before:\s+sshd$/m);
  assert.match(script, /^# Default-Start:\s+2 3 4 5$/m);
});

test('records a persistent legacy userspace boot milestone', () => {
  const helper = fs.readFileSync(firstboot, 'utf8');

  assert.match(helper, /legacy-firstboot-started/);
  assert.match(helper, /legacy-firstboot-ready/);
  assert.match(helper, /legacy-firstboot-failed/);
  assert.match(helper, /dmesg/);
});

test('ships an early initramfs recovery guard', () => {
  assert.equal(fs.existsSync(initrd), true, 'legacy initramfs helper is required');
  const script = fs.readFileSync(initrd, 'utf8');
  assert.match(script, /amlenc-force-recovery/);
  assert.match(script, /mount/);
  assert.match(script, /switch_root/);
});
