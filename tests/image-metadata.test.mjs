import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertImageMetadata,
  createImageMetadata,
  parseImageMetadata,
} from '../scripts/lib/image-metadata.mjs';

const expected = {
  schemaVersion: 1,
  board: 'WS1608 / OneCloud',
  base: 'Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test',
  kernel: '6.12.28-current-meson',
  oneKvmVersion: '0.2.4',
  upstreamTag: 'v260709',
  packageDigest: 'a'.repeat(64),
  buildTag: 'ws1608-one-kvm-0.2.4-v260709-b001',
  buildNumber: 1,
  builderCommit: '0123456789abcdef0123456789abcdef01234567',
};

test('creates and parses deterministic image release metadata', () => {
  const text = createImageMetadata(expected);
  assert.equal(text.endsWith('\n'), true);
  assert.deepEqual(parseImageMetadata(text), {
    schema_version: '1',
    board: expected.board,
    base: expected.base,
    kernel: expected.kernel,
    one_kvm_version: expected.oneKvmVersion,
    one_kvm_release: expected.upstreamTag,
    package_sha256: expected.packageDigest,
    build_tag: expected.buildTag,
    build_number: '1',
    builder_commit: expected.builderCommit,
  });
});

test('accepts metadata only when every expected identity field matches', () => {
  const text = createImageMetadata(expected);
  assert.deepEqual(assertImageMetadata(text, expected), parseImageMetadata(text));
});

test('rejects an altered package digest', () => {
  const text = createImageMetadata(expected).replace(expected.packageDigest, 'b'.repeat(64));
  assert.throws(() => assertImageMetadata(text, expected), /package_sha256/);
});

test('rejects duplicate or unknown metadata keys', () => {
  const text = `${createImageMetadata(expected)}build_number=2\n`;
  assert.throws(() => parseImageMetadata(text), /duplicate key/);

  assert.throws(
    () => parseImageMetadata(`${createImageMetadata(expected)}unexpected=value\n`),
    /unknown key/,
  );
});

test('rejects invalid build identity before writing the image', () => {
  assert.throws(
    () => createImageMetadata({ ...expected, buildNumber: 0 }),
    /positive integer/,
  );
  assert.throws(
    () => createImageMetadata({ ...expected, packageDigest: 'not-a-digest' }),
    /package digest/,
  );
});
