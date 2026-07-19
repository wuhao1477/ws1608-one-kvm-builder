import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const buildScript = fs.readFileSync('scripts/build-image.sh', 'utf8');
const verifyScript = fs.readFileSync('scripts/verify-image.sh', 'utf8');

test('build script requires the immutable build identity', () => {
  assert.match(buildScript, /BUILD_STAMP=\$\{BUILD_STAMP:\?/);
  assert.match(buildScript, /BUILD_TAG=\$\{BUILD_TAG:\?/);
  assert.match(buildScript, /IMAGE_NAME=\$\{IMAGE_NAME:\?/);
  assert.match(buildScript, /"build_tag": "\$BUILD_TAG"/);
  assert.match(buildScript, /"build_stamp": "\$BUILD_STAMP"/);
});

test('build script does not leave an undeclared image checksum sidecar', () => {
  assert.doesNotMatch(buildScript, /OUTPUT_IMAGE\.sha256/);
});

test('image verifier checks build identity, service semantics, and runtime dependencies', () => {
  assert.match(verifyScript, /BUILD_TAG=\$\{BUILD_TAG:\?/);
  assert.match(verifyScript, /BUILD_STAMP=\$\{BUILD_STAMP:\?/);
  assert.match(verifyScript, /build_tag=\$BUILD_TAG/);
  assert.match(verifyScript, /ExecStart=\/usr\/bin\/one-kvm/);
  assert.match(verifyScript, /libasound2t64/);
  assert.match(verifyScript, /one-kvm-enable-otg/);
});
