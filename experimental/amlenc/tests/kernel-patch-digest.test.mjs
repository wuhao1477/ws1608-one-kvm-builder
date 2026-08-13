import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const digestScript = path.resolve('experimental/amlenc/scripts/kernel-patch-digest.sh');

function createPatchDirectory(root, name) {
  const directory = path.join(root, name);
  fs.mkdirSync(directory);
  fs.writeFileSync(path.join(directory, '0001-first.patch'), 'first patch\n');
  fs.writeFileSync(path.join(directory, '0002-second.patch'), 'second patch\n');
  return directory;
}

function digest(directory) {
  const result = spawnSync('bash', [digestScript, directory], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test('computes the same patch digest independently of the directory path', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-patch-digest-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const first = createPatchDirectory(root, 'first');
  const second = createPatchDirectory(root, 'second');

  assert.match(digest(first), /^[a-f0-9]{64}$/);
  assert.equal(digest(first), digest(second));
});

test('changes the patch digest when patch content changes', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'amlenc-patch-digest-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const first = createPatchDirectory(root, 'first');
  const second = createPatchDirectory(root, 'second');
  fs.appendFileSync(path.join(second, '0002-second.patch'), 'changed\n');

  assert.notEqual(digest(first), digest(second));
});
