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
  assert.ok(
    script.indexOf('verify-release-assets.mjs') < script.indexOf('sha256sum --check SHA256SUMS'),
    'structured asset validation must run before sha256sum reads checksum paths',
  );
});

test('release shell entrypoints reject path-bearing artifact names first', () => {
  for (const name of ['scripts/package-release.sh', 'scripts/verify-release-assets.sh']) {
    const script = read(name);
    assert.match(script, /require_basename "\$IMAGE_NAME" IMAGE_NAME/);
    assert.match(script, /require_basename "\$VALIDATION_REPORT_NAME" VALIDATION_REPORT_NAME/);
    assert.ok(script.indexOf('require_basename "$IMAGE_NAME"') < script.indexOf('image="$OUTPUT_DIR/$IMAGE_NAME"'));
  }
});

test('release discovery includes repository tag refs hidden from the draft Release API', () => {
  const script = read('scripts/discover-release.sh');
  assert.match(script, /tags\?per_page=100/);
  assert.match(script, /"\$release_file" "\$releases_file" "\$tags_file" "\$FORCE_BUILD"/);
  assert.match(script, /WORKFLOW_RUN_NUMBER=\$\{GITHUB_RUN_NUMBER:-\}/);
  assert.match(script, /"\$WORKFLOW_RUN_NUMBER" "\$WORKFLOW_RUN_ATTEMPT"/);
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
