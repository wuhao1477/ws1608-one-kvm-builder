import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const root = process.cwd();
const manifestPath = path.join(root, 'experimental/amlenc/config/stable-chain.sha256');
const verifierPath = path.join(root, 'experimental/amlenc/scripts/verify-stable-chain.sh');

function runVerifier(repoRoot, manifest = manifestPath) {
  return spawnSync('bash', [verifierPath, repoRoot, manifest], {
    cwd: root,
    encoding: 'utf8',
  });
}

function manifestEntries() {
  return fs.readFileSync(manifestPath, 'utf8').trim().split('\n').map((line) => {
    const match = line.match(/^([a-f0-9]{64})  ([^/].*)$/);
    assert.ok(match, `invalid stable-chain entry: ${line}`);
    return { digest: match[1], file: match[2] };
  });
}

function copyProtectedRepository(entries) {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-stable-chain-'));
  for (const { file } of entries) {
    const source = path.join(root, file);
    const destination = path.join(fixture, file);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(source, destination);
  }
  const git = spawnSync('git', ['init', '-q', fixture], { encoding: 'utf8' });
  assert.equal(git.status, 0, git.stderr);
  const add = spawnSync('git', ['-C', fixture, 'add', '.'], { encoding: 'utf8' });
  assert.equal(add.status, 0, add.stderr);
  return fixture;
}

test('accepts the complete verified stable build chain', () => {
  assert.equal(fs.existsSync(manifestPath), true, `${manifestPath} must exist`);
  assert.equal(fs.existsSync(verifierPath), true, `${verifierPath} must exist`);

  const result = runVerifier(root);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /^verified \d+ stable-chain files\n$/);
});

test('rejects a changed protected stable file', (t) => {
  const entries = manifestEntries();
  const fixture = copyProtectedRepository(entries);
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  fs.appendFileSync(path.join(fixture, 'config/base.env'), '\n# mutation\n');

  const result = runVerifier(fixture);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /config\/base\.env: FAILED/);
});
