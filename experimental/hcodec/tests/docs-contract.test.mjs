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
  assert.match(text, /full_power_reset/);
});

test('documents run-29-1 multi-frame decode evidence and stability wrapper', () => {
  const text = files.map(read).join('\n');

  assert.match(text, /33987050987/);
  assert.match(text, /run-29-1/);
  assert.match(text, /6866/);
  assert.match(text, /7d50f102b6405fcc637467a61a8c5ef62ef0c90f2af88136a2f9f9ae97f6413f/);
  assert.match(text, /1 IDR.*29 P|29 P.*1 IDR/);
  assert.match(text, /capture-stability-probe\.sh/);
});

test('documents the CNB run-30-1 stability probe evidence and remaining reboot gate', () => {
  const text = files.map(read).join('\n');

  assert.match(text, /cnb-iso-1k218vadk/);
  assert.match(text, /11a490631aaff658b8d590c87a6576a232488d3f/);
  assert.match(text, /run-30-1/);
  assert.match(text, /996855724/);
  assert.match(text, /44137/);
  assert.match(text, /334a7bca58cda061d28ddaf4410bfebec79c0e50d0cd09466ab2929ad288a9a2/);
  assert.match(text, /60.*健康记录|健康记录.*60/);
  assert.match(text, /仍需重启恢复 SSH|探针后设备仍需重启/);
  assert.match(text, /不创建 PR/);
});

test('documents the stable-rootfs rerun and its remaining post-probe loss', () => {
  const text = files.map(read).join('\n');

  assert.match(text, /results-stable-30f/);
  assert.match(text, /44127/);
  assert.match(text, /d1daed2cda6353b1b7d2f692abcf3803ef9076b6e0dc550652bafd66b97e818a/);
  assert.match(text, /稳定 One-KVM 用户空间/);
  assert.match(text, /探针后.*失联|仍失联/);
});

test('does not describe the disproved offset ring workaround as the active next step', () => {
  const text = files.map(read).join('\n');
  assert.doesNotMatch(text, /run-10 只调整 Meson8b offset/);
  assert.doesNotMatch(text, /run-10 offset ring-base 修正后等待/);
});
