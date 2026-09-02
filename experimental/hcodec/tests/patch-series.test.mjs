import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const patchDir = 'experimental/hcodec/patches/linux-6.12';
const referenceDir = 'experimental/hcodec/reference/linux-6.12';
const digestScript = 'experimental/hcodec/scripts/patch-digest.sh';
const applyScript = 'experimental/hcodec/scripts/apply-patches.sh';

test('ships the ordered 18 reference patches plus Meson8b correction and diagnostics', () => {
  const reference = fs.readdirSync(referenceDir).filter((file) => file.endsWith('.patch')).sort();
  const files = fs.readdirSync(patchDir).filter((file) => file.endsWith('.patch')).sort();

  assert.equal(reference.length, 18);
  assert.equal(files.length, 21);
  assert.deepEqual(files.slice(0, 18), reference);
  assert.match(files[0], /^0001-/);
  assert.match(files[17], /^0018-/);
  assert.equal(files[18], '0019-meson8b-hhi-and-dt-fix.patch');
  assert.equal(files[19], '0020-media-meson-add-HCODEC-runtime-diagnostics.patch');
  assert.equal(files[20], '0021-media-meson-add-V4L2-queue-diagnostics.patch');
});

test('runtime diagnostics patch traces the first encode command path', () => {
  const patch = fs.readFileSync(
    `${patchDir}/0020-media-meson-add-HCODEC-runtime-diagnostics.patch`,
    'utf8',
  );

  for (const value of [
    'trace_runtime',
    'meson_venc_trace_runtime',
    'meson_venc_command_name',
    'meson_venc_dump_state',
    'meson_venc_prepare_command',
    'meson_venc_start_cpu',
    'meson_venc_command',
    'meson_venc_irq',
    'meson_venc_device_run',
  ]) {
    assert.match(patch, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
});

test('V4L2 queue diagnostics patch traces the ioctl path before first hardware command', () => {
  const patch = fs.readFileSync(
    `${patchDir}/0021-media-meson-add-V4L2-queue-diagnostics.patch`,
    'utf8',
  );

  for (const value of [
    'meson_venc_queue_setup',
    'meson_venc_buf_prepare',
    'meson_venc_buf_queue',
    'meson_venc_start_streaming',
    'queue_setup:',
    'buf_prepare:',
    'buf_queue:',
    'start_streaming:',
  ]) {
    assert.match(patch, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
});

test('computes a path-independent patch digest', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-patch-digest-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const copies = ['first', 'second'].map((name) => {
    const target = path.join(root, name);
    fs.cpSync(patchDir, target, { recursive: true });
    return target;
  });
  const digest = (directory) => spawnSync('bash', [digestScript, directory], { encoding: 'utf8' });

  const first = digest(copies[0]);
  const second = digest(copies[1]);
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout.trim(), /^[0-9a-f]{64}$/);
  assert.equal(first.stdout, second.stdout);
});

test('applies every patch in lexical order to a git source tree', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-patch-apply-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'source');
  const patches = path.join(root, 'patches');
  fs.mkdirSync(source);
  fs.mkdirSync(patches);
  spawnSync('git', ['init', '-q'], { cwd: source });
  fs.writeFileSync(path.join(source, 'value.txt'), 'zero\n');
  spawnSync('git', ['add', '.'], { cwd: source });
  spawnSync('git', ['-c', 'user.name=test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'base'], { cwd: source });
  fs.writeFileSync(path.join(patches, '0001-one.patch'), 'diff --git a/value.txt b/value.txt\nindex 6b6e7c1..2c43219 100644\n--- a/value.txt\n+++ b/value.txt\n@@ -1 +1 @@\n-zero\n+one\n');
  fs.writeFileSync(path.join(patches, '0002-two.patch'), 'diff --git a/value.txt b/value.txt\nindex 2c43219..f719efd 100644\n--- a/value.txt\n+++ b/value.txt\n@@ -1 +1 @@\n-one\n+two\n');

  const relativePatches = path.relative(process.cwd(), patches);
  const result = spawnSync('bash', [applyScript, source, relativePatches], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(path.join(source, 'value.txt'), 'utf8'), 'two\n');
});
