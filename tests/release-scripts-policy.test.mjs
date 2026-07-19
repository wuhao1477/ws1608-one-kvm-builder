import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

test('packaging creates xz, finalizes metadata, and invokes independent verification', () => {
  const script = read('scripts/package-release.sh');
  assert.match(script, /xz -T0 -9e -c/);
  assert.match(script, /finalize-release\.mjs/);
  assert.match(script, /verify-release-assets\.sh/);
});

test('release verification checks the xz stream, decompressed image, checksums, and manifest', () => {
  const script = read('scripts/verify-release-assets.sh');
  assert.match(script, /xz -t/);
  assert.match(script, /xz -dc/);
  assert.match(script, /sha256sum --check SHA256SUMS/);
  assert.match(script, /verify-release-assets\.mjs/);
  assert.match(script, /compressed image does not match raw image/);
});

test('the metadata CLI verifies all workflow identity fields', () => {
  const script = read('scripts/verify-release-assets.mjs');
  for (const field of [
    'one_kvm_version',
    'one_kvm_release',
    'package_sha256',
    'base_sha256',
    'build_tag',
    'build_number',
    'builder_commit',
    'github_run_id',
  ]) {
    assert.match(script, new RegExp(`${field}:`));
  }
});
