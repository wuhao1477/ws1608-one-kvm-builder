import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const paths = {
  rootfs: 'experimental/amlenc/scripts/build-legacy-rootfs.sh',
  image: 'experimental/amlenc/scripts/build-legacy-bringup-image.sh',
  verify: 'experimental/amlenc/scripts/verify-legacy-bringup-image.sh',
  workflow: '.github/workflows/amlenc-legacy-bringup.yml',
  validate: 'experimental/amlenc/scripts/validate-h264.sh',
};

function read(path) {
  assert.equal(fs.existsSync(path), true, `${path} is required`);
  return fs.readFileSync(path, 'utf8');
}

test('assembles the M8 diagnostic stack into the recovery-first rootfs', () => {
  const rootfs = read(paths.rootfs);
  const image = read(paths.image);
  const verify = read(paths.verify);

  for (const token of ['ENCODER_DIR', 'libvpcodec.so', 'amlenc-m8-diag', 'validate-h264.sh', 'hardware-limits.json']) {
    assert.match(rootfs + image, new RegExp(token.replaceAll('.', '\\.')), `${token} must enter rootfs`);
  }
  for (const token of ['frame-640x480.nv12', 'frame-1280x720.nv12', 'ENCODER_DIR']) {
    assert.match(image + rootfs, new RegExp(token.replaceAll('.', '\\.')), `${token} must be packaged`);
  }
  assert.match(image, /diagnostic_included/);
  for (const path of ['/usr/local/libexec/ws1608-amlenc/amlenc-m8-diag', '/usr/local/lib/ws1608-amlenc/libvpcodec.so', '/usr/local/share/ws1608-amlenc/frame-1280x720.nv12']) {
    assert.match(verify, new RegExp(path.replaceAll('/', '\\/').replaceAll('.', '\\.')), `${path} must be verified`);
  }
  assert.match(verify, /one_kvm_included.*false/);
});

test('builds and verifies the encoder library before the legacy burn image', () => {
  const workflow = read(paths.workflow);

  assert.match(workflow, /Build M8 encoder library/);
  assert.match(workflow, /build-libvpcodec\.sh/);
  assert.match(workflow, /verify-build\.sh libvpcodec/);
  assert.match(workflow, /ENCODER_DIR:/);
  assert.match(workflow, /diagnostic_included.*true/);
});

test('uses an installed hardware-limits path on the target rootfs', () => {
  const validate = read(paths.validate);

  assert.match(validate, /usr\/local\/share\/ws1608-amlenc\/hardware-limits\.json|AMLENC_HARDWARE_LIMITS/);
  assert.match(validate, /AMLENC_HARDWARE_LIMITS/);
});
