#!/usr/bin/env node

import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const patterns = [
  ['private-key', /-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----/],
  ['github-token', /\b(?:ghp|gho|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}\b/],
  ['aws-access-key', /\bAKIA[0-9A-Z]{16}\b/],
  ['bearer-token', /Authorization:\s*Bearer\s+[A-Za-z0-9._~+/=-]{20,}/i],
  ['credential-url', /https?:\/\/[^\s/@:]+:[^\s/@]+@/i],
];

function trackedFiles() {
  const result = spawnSync('git', ['ls-files', '-z'], { encoding: 'buffer' });
  if (result.status !== 0) {
    throw new Error(result.stderr.toString('utf8').trim() || 'git ls-files failed');
  }
  return result.stdout.toString('utf8').split('\0').filter(Boolean);
}

function scanFile(file) {
  const contents = fs.readFileSync(file);
  if (contents.includes(0)) return [];
  const text = contents.toString('utf8');
  return patterns.filter(([, pattern]) => pattern.test(text)).map(([name]) => name);
}

try {
  const findings = trackedFiles().flatMap((file) =>
    scanFile(file).map((pattern) => `${file}: ${pattern}`));
  if (findings.length) {
    process.stderr.write(`tracked credential patterns found:\n${findings.join('\n')}\n`);
    process.exitCode = 1;
  } else {
    process.stdout.write('verified tracked files: no credential patterns\n');
  }
} catch (error) {
  process.stderr.write(`secret scan failed: ${error.message}\n`);
  process.exitCode = 1;
}
