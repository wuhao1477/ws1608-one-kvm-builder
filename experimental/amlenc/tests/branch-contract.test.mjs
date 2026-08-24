import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const limit = 300;
const sourcePattern = /\.(?:mjs|js|cjs|ts|tsx|sh)$/;

function git(args) {
  return spawnSync('git', args, { encoding: 'utf8' });
}

function branchBase() {
  if (process.env.BRANCH_CONTRACT_BASE) return process.env.BRANCH_CONTRACT_BASE;
  for (const ref of ['main', 'origin/main']) {
    const result = git(['merge-base', 'HEAD', ref]);
    if (result.status === 0) return result.stdout.trim();
  }
  throw new Error('branch base is unavailable; fetch full history or set BRANCH_CONTRACT_BASE');
}

test('source files changed by this branch stay within the line-count limit', () => {
  const base = branchBase();
  const result = git(['diff', '--name-only', '--diff-filter=ACMRT', base, '--']);
  assert.equal(result.status, 0, result.stderr);
  const oversized = result.stdout.trim().split('\n')
    .filter((filePath) => sourcePattern.test(filePath) && fs.existsSync(filePath))
    .map((filePath) => [filePath, fs.readFileSync(filePath, 'utf8').split('\n').length - 1])
    .filter(([, lines]) => lines > limit);
  assert.deepEqual(oversized, []);
});
