import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const renderer = 'experimental/amlenc/scripts/render-legacy-trial-boot.mjs';
const armTrial = 'experimental/amlenc/rootfs/ws1608-amlenc-arm-trial';
const markSuccess = 'experimental/amlenc/rootfs/ws1608-amlenc-mark-success';
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

test('renders a recovery-first revision-isolated boot flow', (t) => {
  assert.equal(fs.existsSync(renderer), true, 'legacy boot renderer is required');
  const output = fixture(t);
  const result = spawnSync(process.execPath, [renderer, output, uuid, 'b001001'], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const command = fs.readFileSync(path.join(output, 'boot.cmd'), 'utf8');
  const force = command.indexOf('amlenc-force-recovery');
  const success = command.indexOf('amlenc-3.10.ok');
  const attempted = command.indexOf('amlenc_trial_revision');
  assert.ok(force >= 0 && success > force && attempted > success);
  assert.match(command, /saveenv[\s\S]*run boot_recovery/);
  assert.match(command, /uImage\.recovery/);
  assert.match(command, /uInitrd\.recovery/);
  assert.match(command, /uImage\.amlenc/);
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
  assert.equal(fs.existsSync(path.join(boot, 'amlenc-force-recovery')), false);
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
