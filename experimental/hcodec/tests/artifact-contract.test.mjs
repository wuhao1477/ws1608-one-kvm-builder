import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import test from 'node:test';

const packageScript = 'experimental/hcodec/scripts/package-artifact.sh';
const verifyScript = 'experimental/hcodec/scripts/verify-artifact.sh';
const installScript = 'experimental/hcodec/scripts/install-artifact.sh';
const stabilityProbeScript = 'experimental/hcodec/scripts/capture-stability-probe.sh';
const workflow = '.cnb.yml';

test('packages a single deterministic tar.xz with manifests and kernel/tools payloads', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-artifact-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const kernel = path.join(root, 'kernel');
  const tools = path.join(root, 'tools');
  const firmware = path.join(root, 'firmware');
  const output = path.join(root, 'output');
  fs.mkdirSync(kernel); fs.mkdirSync(tools); fs.mkdirSync(firmware);
  for (const file of ['zImage', 'uImage', 'meson8b-onecloud.dtb', 'modules.tar.xz',
    'kernel.config', 'System.map', 'Module.symvers', 'module-signing.json', 'SHA256SUMS'])
    fs.writeFileSync(path.join(kernel, file), file);
  for (const file of ['meson-venc-smoke', 'meson-venc-capture', 'tools-manifest.json',
    'firmware-manifest.json', 'SHA256SUMS']) fs.writeFileSync(path.join(tools, file), file);
  fs.writeFileSync(path.join(kernel, 'source-manifest.json'), JSON.stringify({
    linux_commit: 'linux', armbian_build_commit: 'armbian', kernel_release: '6.12.28-current-meson',
    patches_sha256: '1'.repeat(64), toolchain_container: 'ubuntu:24.04@sha256:test'
  }));
  fs.writeFileSync(path.join(kernel, 'SHA256SUMS'), `${'2'.repeat(64)}  meson8b-onecloud.dtb\n`);
  fs.writeFileSync(path.join(tools, 'tools-manifest.json'), JSON.stringify({ schema: 1, abi: 'glibc' }));
  const firmwareBytes = Buffer.alloc(9536, 0x5a);
  fs.writeFileSync(path.join(firmware, 'meson8b_h264.bin'), firmwareBytes);
  const firmwareSha256 = crypto.createHash('sha256').update(firmwareBytes).digest('hex');
  fs.writeFileSync(path.join(firmware, 'firmware-manifest.json'), JSON.stringify({
    schema: 1, variant: 'meson8b_dblk', repository: 'https://github.com/hardkernel/linux.git',
    commit: '5aed95d35d252cafc75ce613a3a0052285662de2',
    archive_sha256: '0'.repeat(64), input_path: 'drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h',
    word_count: 2384, output_size: 9536,
    output_sha256: firmwareSha256,
    binary_included: true, redistribution: 'unverified',
  }));
  const result = spawnSync('bash', [packageScript, kernel, tools, firmware, output, '12', '2'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readdirSync(output).length, 3);
  const artifact = path.join(output, 'ws1608-hcodec-armv7-run-12-2.tar.xz');
  const contents = spawnSync('tar', ['-tJf', artifact], { encoding: 'utf8' });
  assert.equal(contents.status, 0, contents.stderr);
  assert.match(contents.stdout, /\.\/capture-probe\.sh/);
  assert.match(contents.stdout, /\.\/capture-stability-probe\.sh/);
  assert.match(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'), /hardware_boot_tested.*false/);
  assert.equal(spawnSync('bash', [verifyScript, output], { encoding: 'utf8' }).status, 0);
  assert.match(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'), /firmware_sha256/);
});

test('ships a staged module installer that preserves target system links', () => {
  const text = fs.readFileSync(installScript, 'utf8');
  assert.match(text, /modules-stage/);
  assert.match(text, /lib\/modules\/\$KERNEL_RELEASE/);
  assert.doesNotMatch(text, /tar -xJf [^\n]+ -C \/(?:\s|$)/);
});

test('ships a rootfs-persistent kernel trace probe wrapper', () => {
  const source = fs.readFileSync(packageScript, 'utf8');
  const verifier = fs.readFileSync(verifyScript, 'utf8');

  assert.match(source, /capture-probe\.sh/);
  assert.match(verifier, /\.\/capture-probe\.sh/);
});

test('stability probe persists sixty post-probe health records', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-stability-probe-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  const results = path.join(root, 'results');
  const smoke = path.join(root, 'smoke');
  const output = path.join(results, 'stream.h264');
  fs.mkdirSync(bin);
  for (const command of ['dmesg', 'sleep', 'sync']) {
    const file = path.join(bin, command);
    fs.writeFileSync(file, '#!/bin/sh\nexit 0\n');
    fs.chmodSync(file, 0o755);
  }
  fs.writeFileSync(smoke, '#!/bin/sh\nprintf annexb > "$2"\n');
  fs.chmodSync(smoke, 0o755);

  const result = spawnSync('bash', [stabilityProbeScript, results, smoke, '/dev/video0', output], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(path.join(results, 'kernel.after.log')), true);
  const records = fs.readFileSync(path.join(results, 'health.log'), 'utf8').trim().split('\n');
  assert.equal(records.length, 60);
  assert.match(records[0], /uptime=.* eth0=.* carrier=/);
});

test('workflow only runs on pull requests or manual dispatch and keeps artifact isolated', () => {
  const text = fs.readFileSync(workflow, 'utf8');
  assert.match(text, /"codex\/hcodec-\*":/);
  assert.match(text, /\s+push:/);
  assert.match(text, /\s+pull_request:/);
  assert.match(text, /web_trigger_hcodec/);
  assert.doesNotMatch(text, /schedule:|repository_dispatch:|create-release|gh release/);
  const runner = fs.readFileSync('scripts/cnb-run-hcodec.sh', 'utf8');
  assert.match(runner, /package-artifact\.sh/);
  assert.match(runner, /verify-artifact\.sh/);
  const pipeline = fs.readFileSync(workflow, 'utf8');
  assert.match(pipeline, /image: cnbcool\/attachments:latest/);
  assert.match(pipeline, /out\/hcodec\/artifact\/\*/);
  assert.match(pipeline, /ttl: 14/);
  assert.match(pipeline, /cnb-download-commit-assets\.sh/);
  assert.doesNotMatch(runner, /cnb-upload-commit-assets\.sh/);
});

test('workflow keeps generated Meson8b firmware as a separate package input', () => {
  const runner = fs.readFileSync('scripts/cnb-run-hcodec.sh', 'utf8');
  assert.match(runner, /build-firmware\.sh/);
  assert.match(runner, /out\/hcodec\/firmware/);
});

test('artifact verifier whitelists only the explicit Meson8b firmware payload', () => {
  const source = fs.readFileSync(verifyScript, 'utf8');
  assert.match(source, /\.\/firmware\/meson8b_h264\.bin/);
  assert.match(source, /\.\/firmware\/firmware-manifest\.json/);
  assert.match(source, /binary_included.*true|true.*binary_included/);
});
