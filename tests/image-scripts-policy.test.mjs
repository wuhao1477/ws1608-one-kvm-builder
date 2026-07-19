import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const buildScript = fs.readFileSync('scripts/build-image.sh', 'utf8');
const manifestScript = fs.readFileSync('scripts/write-image-manifest.mjs', 'utf8');
const verifyScript = fs.readFileSync('scripts/verify-image.sh', 'utf8');
const baseConfig = fs.readFileSync('config/base.env', 'utf8');

test('the base configuration is the source of image identity fields', () => {
  for (const field of ['BASE_ID', 'BASE_FLAVOR', 'BASE_KERNEL', 'BASE_BOARD']) {
    assert.match(baseConfig, new RegExp(`^${field}=`, 'm'));
  }
});

test('the image builder requires and embeds immutable build provenance', () => {
  for (const variable of ['BUILD_TAG', 'BUILD_NUMBER', 'PACKAGE_DIGEST', 'BUILDER_COMMIT']) {
    assert.match(buildScript, new RegExp(`${variable}=\\$\\{${variable}:\\?`));
  }
  assert.match(buildScript, /write-image-metadata\.mjs/);
  assert.match(buildScript, /One-KVM_\$\{image_identity\}_\$\{BASE_FLAVOR\}\.burn\.img/);
  assert.match(manifestScript, /build_tag: process\.env\.BUILD_TAG/);
  assert.match(manifestScript, /build_number: Number\(process\.env\.BUILD_NUMBER\)/);
});

test('the independent verifier checks exact identity and installed files', () => {
  for (const variable of [
    'UPSTREAM_TAG',
    'PACKAGE_DIGEST',
    'BUILD_TAG',
    'BUILD_NUMBER',
    'BUILDER_COMMIT',
    'VALIDATION_REPORT',
  ]) {
    assert.match(verifyScript, new RegExp(`${variable}=\\$\\{${variable}:\\?`));
  }
  assert.match(verifyScript, /verify-image-metadata\.mjs/);
  assert.match(verifyScript, /test "\$service_link" = \/lib\/systemd\/system\/one-kvm\.service/);
  assert.match(verifyScript, /cmp "\$ROOT_DIR\/config\/one-kvm-enable-otg"/);
  assert.match(verifyScript, /cmp "\$ROOT_DIR\/config\/one-kvm-otg\.service"/);
  assert.match(verifyScript, /cmp "\$ROOT_DIR\/config\/one-kvm\.service\.d-otg\.conf"/);
  assert.match(verifyScript, /test ! -e "\$MOUNT_DIR\/tmp\/one-kvm\.deb"/);
  assert.match(verifyScript, /test ! -e "\$MOUNT_DIR\/usr\/bin\/qemu-arm-static"/);
  assert.match(verifyScript, /write-validation-report\.mjs/);
});
