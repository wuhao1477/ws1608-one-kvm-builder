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

test('ships the ordered 18 reference patches plus one Meson8b correction', () => {
  const reference = fs.readdirSync(referenceDir).filter((file) => file.endsWith('.patch')).sort();
  const files = fs.readdirSync(patchDir).filter((file) => file.endsWith('.patch')).sort();

  assert.equal(reference.length, 18);
  assert.equal(files.length, 19);
  assert.deepEqual(files.slice(0, 18), reference);
  assert.match(files[0], /^0001-/);
  assert.match(files[17], /^0018-/);
  assert.equal(files[18], '0019-meson8b-hhi-and-dt-fix.patch');
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
