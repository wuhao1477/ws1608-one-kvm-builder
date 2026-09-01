import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const packageScript = 'experimental/hcodec/scripts/package-artifact.sh';
const verifyScript = 'experimental/hcodec/scripts/verify-artifact.sh';
const workflow = '.github/workflows/hcodec-candidate.yml';

test('packages a single deterministic tar.xz with manifests and kernel/tools payloads', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-artifact-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const kernel = path.join(root, 'kernel');
  const tools = path.join(root, 'tools');
  const output = path.join(root, 'output');
  fs.mkdirSync(kernel); fs.mkdirSync(tools);
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
  const result = spawnSync('bash', [packageScript, kernel, tools, output, '12', '2'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readdirSync(output).length, 3);
  assert.match(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'), /hardware_boot_tested.*false/);
  assert.equal(spawnSync('bash', [verifyScript, output], { encoding: 'utf8' }).status, 0);
});

test('workflow only runs on pull requests or manual dispatch and keeps artifact isolated', () => {
  const text = fs.readFileSync(workflow, 'utf8');
  assert.match(text, /pull_request:/);
  assert.match(text, /workflow_dispatch:/);
  assert.doesNotMatch(text, /schedule:|repository_dispatch:|create-release|gh release/);
  assert.match(text, /ubuntu:24\.04@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316/);
  assert.match(text, /retention-days:\s*14/);
  assert.match(text, /package-artifact\.sh/);
  assert.match(text, /verify-artifact\.sh/);
  assert.match(text, /download-artifact/);
});
