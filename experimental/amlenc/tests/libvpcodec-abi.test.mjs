import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const files = {
  build: 'experimental/amlenc/scripts/build-libvpcodec.sh',
  verify: 'experimental/amlenc/scripts/verify-libvpcodec.sh',
  m8Patch: 'experimental/amlenc/patches/libencoder/0001-enable-m8-armhf.patch',
  abiPatch: 'experimental/amlenc/patches/libencoder/0002-one-kvm-abi-v1.patch',
  diagnostic: 'experimental/amlenc/tools/amlenc-m8-diag.cpp',
  exports: 'experimental/amlenc/config/libvpcodec.exports',
  licensing: 'experimental/amlenc/docs/licensing.md',
  digest: 'experimental/amlenc/scripts/libencoder-patch-digest.sh',
  verifyBuild: 'experimental/amlenc/scripts/verify-build.sh',
};

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

test('builds only the 32-bit M8 H.264 implementation', () => {
  const patch = readRequired(files.m8Patch);
  const build = readRequired(files.build);

  assert.match(patch, /enc\/m8_enc\/m8venclib\.cpp/);
  assert.match(patch, /enc\/m8_enc_fast\/m8venclib_fast\.cpp/);
  assert.match(patch, /M8_FAST/);
  assert.doesNotMatch(patch, /^\+.*enc\/gx_enc_fast/m);
  assert.doesNotMatch(build, /aarch64|hevc|h265/i);
  assert.match(build, /arm-linux-gnueabihf-(?:gcc|g\+\+)-7/);
});

test('exposes exactly the One-KVM AMLENC ABI v1 symbols', () => {
  const patch = readRequired(files.abiPatch);
  const exports = readRequired(files.exports);
  const verify = readRequired(files.verify);

  assert.match(patch, /one_kvm_amlenc_abi_version/);
  assert.match(patch, /vl_video_encoder_init\([^\n]*width[^\n]*height[^\n]*frame_rate[^\n]*bit_rate[^\n]*gop[^\n]*img_format/);
  assert.match(patch, /vl_video_encoder_destory/);
  for (const symbol of [
    'one_kvm_amlenc_abi_version',
    'vl_video_encoder_init',
    'vl_video_encoder_encode',
    'vl_video_encoder_destory',
  ]) {
    assert.match(exports, new RegExp(`\\b${symbol};`));
  }
  assert.match(exports, /local:\s*\*/);
  assert.match(verify, /readelf.*-Ws/);
  assert.match(verify, /qemu-arm/);
  assert.match(readRequired(files.verifyBuild), /libvpcodec[\s\S]*verify-libvpcodec\.sh/);
});

test('computes a path-independent libencoder patch digest', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'libencoder-patch-digest-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const directories = ['first', 'second'].map((name) => {
    const directory = path.join(root, name);
    fs.mkdirSync(directory);
    fs.writeFileSync(path.join(directory, '0001-m8.patch'), 'm8\n');
    fs.writeFileSync(path.join(directory, '0002-abi.patch'), 'abi\n');
    return directory;
  });
  const digest = (directory) => {
    const result = spawnSync('bash', [files.digest, directory], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };

  assert.match(digest(directories[0]), /^[a-f0-9]{64}$/);
  assert.equal(digest(directories[0]), digest(directories[1]));
});

test('builds a bounded M8 diagnostic with stream gates', () => {
  const diagnostic = readRequired(files.diagnostic);

  for (const option of ['--input', '--width', '--height', '--fps', '--bitrate', '--frames', '--output']) {
    assert.match(diagnostic, new RegExp(option));
  }
  assert.match(diagnostic, /\/dev\/amvenc_avc/);
  assert.match(diagnostic, /SPS/);
  assert.match(diagnostic, /PPS/);
  assert.match(diagnostic, /IDR/);
  assert.match(diagnostic, /frame size|input size/i);
  assert.match(diagnostic, /zero output|empty output/i);
});

test('keeps unlicensed vendor binaries out of public releases', () => {
  const licensing = readRequired(files.licensing);

  assert.match(licensing, /local-test-only/);
  assert.match(licensing, /libvpcodec\.so/);
  assert.match(licensing, /amlenc-m8-diag/);
  assert.match(licensing, /not found|not present|missing/i);
});
