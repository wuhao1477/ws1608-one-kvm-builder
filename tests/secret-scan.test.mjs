import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const scanner = path.resolve('scripts/verify-secrets.mjs');

function repository(contents) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-secret-scan-'));
  fs.writeFileSync(path.join(root, 'fixture.txt'), contents);
  spawnSync('git', ['init', '-q'], { cwd: root });
  spawnSync('git', ['add', 'fixture.txt'], { cwd: root });
  return root;
}

function run(root) {
  return spawnSync(process.execPath, [scanner], { cwd: root, encoding: 'utf8' });
}

test('rejects a private key in a tracked file', (t) => {
  const root = repository(`-----BEGIN OPENSSH ${'PRIVATE KEY'}-----\nsecret\n`);
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const result = run(root);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /private-key/);
});

test('rejects a GitHub token in a tracked file', (t) => {
  const root = repository(`token=${'ghp_'}123456789012345678901234567890123456\n`);
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const result = run(root);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /github-token/);
});

test('accepts runtime variables and public digests', (t) => {
  const root = repository([
    'CNB_TOKEN=${CNB_TOKEN:?required}',
    'Authorization: Bearer $CNB_TOKEN',
    'sha256=6881000c3bd150a52bd0f77e76b51c31a2f918862caa17fd2fda7cd00ff27f17',
  ].join('\n'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const result = run(root);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /verified tracked files/);
});
