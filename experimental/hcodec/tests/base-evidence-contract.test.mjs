import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const collector = 'experimental/hcodec/scripts/collect-base-evidence.sh';
const stableVerifier = 'experimental/amlenc/scripts/verify-stable-chain.sh';
const protectedManifest = 'experimental/hcodec/config/protected-files.sha256';

function fixture(t, kernelCommit = 'f08cdc6cc92e3d23a05745f0f12f8caa348a27b4') {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-base-evidence-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const input = path.join(directory, 'input');
  const output = path.join(directory, 'output');
  fs.mkdirSync(input);
  fs.writeFileSync(path.join(input, 'armbian-release'), [
    'BOARD=onecloud',
    'BOARDFAMILY=meson8b',
    'ARCH=arm',
    'VERSION=26.8.0-trunk.413',
    'BUILD_REPOSITORY_COMMIT=fa7a7b229',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(input, 'linux-image-metadata'), [
    'Version: 26.8.0-trunk.413',
    `git revision "${kernelCommit}"`,
    '.config hash "8bd94fb6ccbfc1ae"',
    'patches hash "ca1a33f8b63ed656"',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(input, 'kernel.config'), [
    '# CONFIG_MODULE_SIG is not set',
    'CONFIG_SYSTEM_TRUSTED_KEYRING=y',
    'CONFIG_SYSTEM_TRUSTED_KEYS=""',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(input, 'kernel.config.sha256'), '4fbdf08f40fe06be1339f7bcc326c71177f81225302801127b4d7371aca24ea9\n');
  fs.writeFileSync(path.join(input, 'uimage-header.json'), JSON.stringify({
    load_address: '0x00208000',
    entry_point: '0x00208000',
    boot_load_address: '0x20800000',
  }));
  fs.writeFileSync(path.join(input, 'armbianEnv.txt'), 'console=both\nrootdev=UUID=fixture\n');
  fs.writeFileSync(path.join(input, 'boot.cmd'), 'fatload ${bootdev} 0x20800000 /uImage\n');
  fs.writeFileSync(path.join(input, 'dtb.sha256'), '898900ea47a5b8963cb9c5af023cfa6ab405fa2c4954dd1b06585591dc59aa75\n');
  return { input, output };
}

test('validates a uniquely mapped stable Armbian kernel baseline', (t) => {
  const { input, output } = fixture(t);

  const result = spawnSync('bash', [collector, 'verify', input, output], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const manifest = JSON.parse(fs.readFileSync(path.join(output, 'evidence-manifest.json'), 'utf8'));
  assert.equal(manifest.armbian_build_commit, 'fa7a7b2294d9e760a77630950afd460b7a0b2a26');
  assert.equal(manifest.linux_commit, 'f08cdc6cc92e3d23a05745f0f12f8caa348a27b4');
  assert.equal(manifest.module_signing, 'disabled');
  assert.equal(manifest.uimage.load_address, '0x00208000');
});

test('rejects a kernel commit that does not match the source lock', (t) => {
  const { input, output } = fixture(t, '0000000000000000000000000000000000000000');

  const result = spawnSync('bash', [collector, 'verify', input, output], { encoding: 'utf8' });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /kernel commit does not match/);
  assert.equal(fs.existsSync(path.join(output, 'evidence-manifest.json')), false);
});

test('protects the exact stable workflow, config, scripts, and tests', () => {
  const result = spawnSync('bash', [stableVerifier, '.', protectedManifest], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /verified 42 stable-chain files/);
});

test('collect mode rejects a missing immutable base image input', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-base-collect-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));

  const result = spawnSync('bash', [collector, 'collect', directory], {
    encoding: 'utf8',
    env: { ...process.env, BASE_IMAGE_XZ: '' },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /BASE_IMAGE_XZ is required/);
});
