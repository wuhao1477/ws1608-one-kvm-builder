import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const files = [
  'README.md',
  'docs/HANDOFF.md',
  'docs/troubleshooting.md',
  'experimental/hcodec/docs/build.md',
  'experimental/hcodec/docs/artifact.md',
];

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

test('documents the failed run-12-1 evidence and the new Meson8b firmware source', () => {
  const text = files.map(read).join('\n');
  assert.match(text, /run-12-1/);
  assert.match(text, /5aed95d35d252cafc75ce613a3a0052285662de2/);
  assert.match(text, /2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368/);
  assert.match(text, /9536/);
  assert.match(text, /640x480/);
  assert.match(text, /不创建 PR|不得创建 PR|不创建或合并 PR/);
});

test('does not describe the disproved offset ring workaround as the active next step', () => {
  const text = files.map(read).join('\n');
  assert.doesNotMatch(text, /run-10 只调整 Meson8b offset/);
  assert.doesNotMatch(text, /run-10 offset ring-base 修正后等待/);
});
