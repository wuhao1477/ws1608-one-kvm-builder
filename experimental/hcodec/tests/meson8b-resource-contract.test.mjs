import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const correction = 'experimental/hcodec/patches/linux-6.12/0019-meson8b-hhi-and-dt-fix.patch';
const patchDir = 'experimental/hcodec/patches/linux-6.12';

test('patch series supplies the complete standalone Meson8b HCODEC resources', () => {
  const patch = fs.readdirSync(patchDir)
    .filter((file) => file.endsWith('.patch'))
    .sort()
    .map((file) => fs.readFileSync(`${patchDir}/${file}`, 'utf8'))
    .join('\n');

  for (const value of ['amlogic,meson8b-hcodec', 'amlogic,ao-sysctrl',
    'amlogic,canvas', 'CLKID_VDEC_HCODEC', 'interrupt-names', 'clock-names', 'status = "okay"']) {
    assert.match(patch, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.doesNotMatch(patch, /amvenc_avc|libvpcodec|ONE_KVM|modprobe/);
});

test('correction only enables the existing HCODEC node on OneCloud', () => {
  const patch = fs.readFileSync(correction, 'utf8');
  const changed = [...patch.matchAll(/^diff --git a\/(\S+) b\/\S+$/gm)].map((match) => match[1]);

  assert.deepEqual(changed, ['arch/arm/boot/dts/amlogic/meson8b-onecloud.dts']);
  assert.match(patch, /&venc \{[\s\S]*status = "okay";[\s\S]*\};/);
  assert.doesNotMatch(patch, /direct_hhi_clock|regmap_hhi|amlogic,hhi-sysctrl/);
});
