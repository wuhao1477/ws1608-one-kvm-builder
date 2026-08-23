import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const patchPath = 'experimental/amlenc/patches/stable-kernel/0001-amlenc-6.12-research-boundary.patch';
const verifierPath = 'experimental/amlenc/scripts/verify-stable-kernel-boundary.sh';
const sourcesPath = 'experimental/amlenc/config/sources.env';

test('defines a disabled 6.12 AMLENC research module without changing the stable DTB', () => {
  assert.equal(fs.existsSync(patchPath), true, 'stable-kernel research patch is required');
  assert.equal(fs.existsSync(verifierPath), true, 'stable-kernel boundary verifier is required');
  const patch = fs.readFileSync(patchPath, 'utf8');
  const verifier = fs.readFileSync(verifierPath, 'utf8');
  const sources = fs.readFileSync(sourcesPath, 'utf8');

  assert.match(sources, /^STABLE_KERNEL_VERSION=6\.12\.28-current-meson$/m);
  assert.match(patch, /VIDEO_MESON8B_AMLENC_RESEARCH/);
  assert.match(patch, /default n/);
  assert.match(patch, /amlogic,meson8b-amvenc/);
  assert.match(patch, /amvenc_avc/);
  assert.doesNotMatch(patch, /arch\/arm\/boot\/dts|meson8b.*\.dts/i);
  assert.match(verifier, /6\.12\.28-current-meson/);
  assert.match(verifier, /default n/);
  assert.match(verifier, /arch\/arm\/boot\/dts/);
});
