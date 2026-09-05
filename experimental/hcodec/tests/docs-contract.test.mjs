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

test('documents the failed run-15-1 Assist interrupt candidate', () => {
  const text = files.map(read).join('\n');
  assert.match(text, /run-15-1/);
  assert.match(text, /33874935950/);
  assert.match(text, /INT1.*0x19/);
  assert.match(text, /0 字节/);
  assert.match(text, /设备.*失联|No route to host/);
});

test('documents run-16-1 valid payload and streamoff cleanup blockage', () => {
  const text = files.map(read).join('\n');
  assert.match(text, /run-16-1/);
  assert.match(text, /33893613040/);
  assert.match(text, /6547/);
  assert.match(text, /STREAMOFF/);
  assert.match(text, /af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a/);
  assert.match(text, /hardware_encoder_tested.*false/);
});

test('documents run-24-1 module-index recovery and persistent probe evidence', () => {
  const text = files.map(read).join('\n');

  assert.match(text, /33967514846/);
  assert.match(text, /run-24-1/);
  assert.match(text, /armbian-zram-config/);
  assert.match(text, /capture-probe\.sh/);
});

test('documents run-25-1 power-off completion and Meson8b gate experiment', () => {
  const text = files.map(read).join('\n');

  assert.match(text, /33973657980/);
  assert.match(text, /run-25-1/);
  assert.match(text, /power_off end/);
  assert.match(text, /retain_internal_gates/);
});

test('does not describe the disproved offset ring workaround as the active next step', () => {
  const text = files.map(read).join('\n');
  assert.doesNotMatch(text, /run-10 只调整 Meson8b offset/);
  assert.doesNotMatch(text, /run-10 offset ring-base 修正后等待/);
});
