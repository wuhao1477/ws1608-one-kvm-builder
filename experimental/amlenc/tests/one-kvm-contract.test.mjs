import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const files = {
  softwareCodecs: 'experimental/amlenc/config/software-codecs.json',
  patch: 'experimental/amlenc/patches/one-kvm/0001-detect-meson8b-armv7.patch',
  buildEnvPatch: 'experimental/amlenc/patches/one-kvm/0002-pin-armv7-build-inputs.patch',
  cargoLock: 'experimental/amlenc/locks/one-kvm/Cargo.lock',
  frontendLock: 'experimental/amlenc/locks/one-kvm/pnpm-lock.yaml',
  build: 'experimental/amlenc/scripts/build-one-kvm.sh',
  verify: 'experimental/amlenc/scripts/verify-one-kvm.sh',
  verifyMetadata: 'experimental/amlenc/scripts/verify-one-kvm-metadata.mjs',
  digest: 'experimental/amlenc/scripts/one-kvm-patch-digest.sh',
  prepareCrossImage: 'experimental/amlenc/scripts/prepare-one-kvm-cross-image.sh',
  sources: 'experimental/amlenc/config/sources.env',
};

test('locks the four software codec inputs and FFmpeg decoder gates', () => {
  const manifest = JSON.parse(readRequired(files.softwareCodecs));
  assert.deepEqual(manifest, {
    schema: 1,
    codecs: [
      { id: 'h264', encoder: 'libx264', decoder: 'h264' },
      { id: 'h265', encoder: 'libx265', decoder: 'hevc' },
      { id: 'vp8', encoder: 'libvpx_vp8', decoder: 'vp8' },
      { id: 'vp9', encoder: 'libvpx_vp9', decoder: 'vp9' },
    ],
  });
  const sources = readRequired(files.sources);
  assert.match(sources, /^ONE_KVM_LIBVPX_COMMIT=1024874c5919305883187e2953de8fcb4c3d7fa6$/m);
  assert.match(sources, /^ONE_KVM_X265_COMMIT=07295ba7ab551bb9c1580fdaee3200f1b45711b7$/m);
  const patch = readRequired(files.buildEnvPatch);
  assert.match(patch, /ARG LIBVPX_REV=1024874c5919305883187e2953de8fcb4c3d7fa6/);
  assert.match(patch, /ARG X265_REV=07295ba7ab551bb9c1580fdaee3200f1b45711b7/);
  for (const decoder of ['h264', 'hevc', 'vp8', 'vp9']) assert.match(patch, new RegExp(`--enable-decoder=${decoder}`));
});

const expectedMetadata = {
  schema: 1,
  channel: 'experimental',
  upstream_repository: 'https://github.com/mofeng-git/One-KVM.git',
  upstream_ref: 'v260802',
  upstream_commit: 'a4073d64cb49a1404df49e7813b73dd9f78d0931',
  one_kvm_version: '0.2.6',
  package_version: '0.2.6+ws1608amlenc.test001',
  patches_sha256: 'a'.repeat(64),
  dependency_locks_sha256: 'b'.repeat(64),
  rust_toolchain: '1.97.1',
  rustc_commit: '8bab26f4f68e0e26f0bb7960be334d5b520ea452',
  pnpm_version: '10.15.0',
  source_date_epoch: 1785659915,
  build_container: 'debian:11@sha256:2bd63443d521dda488543a2dac4755995cab3e999eb765cec8d800825f692964',
  toolchain: { gcc: '10.2.1', binutils: '2.35.2' },
  dependencies: {
    x264: 'c24e06c2e184345ceb33eb20a15d1024d9fd3497',
    rkmpp: 'a9380ef333102ac318628f83b5f7a460d377749e',
    rkrga: '1d330cc28551943bed3380261a5a9c6fbd58ff53',
  },
  platform: 'WS1608/S805/Meson8b/armv7',
  codec: 'h264_amlenc',
  amlenc_smoke_test_default: false,
  hardware_encoder_tested: false,
  stable_channel_modified: false,
  redistribution: 'local-test-only',
};

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

test('adds a separate Meson8b ARMv7 H.264 capability', () => {
  const patch = readRequired(files.patch);

  assert.match(patch, /target_arch = "arm"/);
  for (const compatible of ['amlogic,meson8b', 'AMLOGIC,8726_M8B', 'm8b_m201_1G']) {
    assert.match(patch, new RegExp(compatible, 'i'));
  }
  assert.match(patch, /Meson8bS805/);
  assert.match(patch, /AmlencCodec::H264/);
  assert.match(patch, /supports_codec/);
  assert.match(patch, /amlenc::smoke_test/);
  assert.match(patch, /ONE_KVM_AMLENC_SMOKE_TEST/);
  assert.match(patch, /allow\(dead_code\)[\s\S]*is_s912_gxm_compatible/);
  assert.match(patch, /src\/video\/pipeline\/shared\.rs/);
  assert.match(patch, /target_arch = "arm"[\s\S]*AMLENC_MAX_FPS: u32 = 30/);
});

test('keeps the AMLENC hardware smoke test opt-in', () => {
  const patch = readRequired(files.patch);
  const build = readRequired(files.build);

  assert.match(patch, /ONE_KVM_AMLENC_SMOKE_TEST/);
  assert.match(patch, /as_deref\(\)\s*==\s*Some\("1"\)/);
  assert.match(build, /amlenc_smoke_test_default:false/);
  assert.doesNotMatch(build, /Environment=ONE_KVM_AMLENC_SMOKE_TEST/);
});

test('does not expose H.265 AMLENC on Meson8b', () => {
  const patch = readRequired(files.patch);

  assert.match(
    patch,
    /(?:Self::)?Meson8bS805\s*=>\s*codec\s*==\s*AmlencCodec::H264/,
  );
  assert.match(patch, /(?:Self::)?S912Gxm\s*=>\s*true/);
});

test('builds a pinned and traceable armhf Debian package', () => {
  const build = readRequired(files.build);
  const buildEnvPatch = readRequired(files.buildEnvPatch);
  const cargoLock = readRequired(files.cargoLock);
  const frontendLock = readRequired(files.frontendLock);

  assert.match(build, /ONE_KVM_COMMIT/);
  assert.match(build, /ONE_KVM_ARCHIVE_SHA256/);
  assert.match(build, /armv7-unknown-linux-gnueabihf/);
  assert.match(build, /VERSION="\$\{ONE_KVM_VERSION\}\+ws1608amlenc\.\$\{BUILD_NUMBER\}"/);
  assert.match(build, /git -C "\$SOURCE_DIR" apply --check/);
  assert.match(build, /one-kvm-patch-digest\.sh/);
  assert.match(build, /package-deb\.sh" armhf/);
  assert.match(build, /pnpm@\$PNPM_VERSION" install --frozen-lockfile/);
  assert.match(build, /pnpm@\$PNPM_VERSION" run build/);
  assert.ok(
    build.indexOf('run build') < build.indexOf('build --locked'),
    'web/dist must be created before RustEmbed compiles the binary',
  );
  assert.match(build, /\"\$BUILD_DRIVER\" build --locked --release/);
  assert.match(build, /AMLENC_BUILD_DRIVER:-cross/);
  assert.match(build, /prepare-one-kvm-cross-image\.sh/);
  assert.match(build, /cd "\$SOURCE_DIR"[\s\S]*PACKAGE_VERSION="\$VERSION" node/);
  assert.match(build, /RUST_TOOLCHAIN=\$ONE_KVM_RUST_TOOLCHAIN/);
  assert.match(build, /PNPM_VERSION=\$ONE_KVM_PNPM_VERSION/);
  assert.match(build, /SOURCE_DATE_EPOCH=\$\{SOURCE_DATE_EPOCH:-\$ONE_KVM_SOURCE_DATE_EPOCH\}/);
  assert.match(build, /find "\$package_dir" -exec touch -h -d "@\$SOURCE_DATE_EPOCH"/);
  assert.match(build, /dpkg-deb --root-owner-group -Zxz -z9 -b/);
  assert.match(build, /--argjson epoch "\$SOURCE_DATE_EPOCH"/);
  assert.match(build, /dependency_locks_sha256/);
  assert.match(cargoLock, /^version = 4$/m);
  assert.match(frontendLock, /^lockfileVersion: '9\.0'$/m);
  assert.match(build, /DEBIAN/);
  assert.match(build, /ws1608-amlenc-build\.json/);
  assert.match(build, /hardware_encoder_tested/);
  assert.match(build, /false/);
  for (const commit of [
    'c24e06c2e184345ceb33eb20a15d1024d9fd3497',
    'a9380ef333102ac318628f83b5f7a460d377749e',
    '1d330cc28551943bed3380261a5a9c6fbd58ff53',
  ]) {
    assert.match(buildEnvPatch, new RegExp(commit));
  }
  assert.match(buildEnvPatch, /Acquire::Retries "5"/);
  assert.match(buildEnvPatch, /ARG RUST_TOOLCHAIN=1\.97\.1/);
  assert.match(buildEnvPatch, /--default-toolchain \$\{RUST_TOOLCHAIN\}/);
});

test('independently verifies package identity, interpreter and metadata', () => {
  const verify = readRequired(files.verify);

  assert.match(verify, /One-KVM package verification failed/);
  assert.match(verify, /ELF interpreter/);
  for (const field of ['Package', 'Version', 'Architecture']) {
    assert.match(verify, new RegExp(`dpkg-deb -f .* ${field}`));
  }
  assert.match(verify, /readelf.*-l/);
  assert.match(verify, /\/lib\/ld-linux-armhf\.so\.3/);
  assert.match(verify, /dpkg-deb -x/);
  assert.match(verify, /ws1608-amlenc-build\.json/);
  assert.match(verify, /hardware_encoder_tested/);
  assert.match(verify, /stable_channel_modified/);
  assert.match(verify, /dependency_locks_sha256/);
  assert.match(verify, /one-kvm-patch-digest\.sh/);
  assert.match(verify, /source .*sources\.env/);
  assert.match(verify, /\.upstream_commit == \$upstream_commit/);
  assert.match(verify, /\.patches_sha256 == \$patches_sha256/);
  assert.match(verify, /\.dependency_locks_sha256 == \$dependency_locks_sha256/);
  assert.match(verify, /rust_toolchain/);
  assert.match(verify, /pnpm_version/);
  assert.match(verify, /sha256sum --check/);
});

test('accepts complete pinned One-KVM provenance metadata', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-one-kvm-metadata-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const metadataPath = path.join(fixture, 'metadata.json');
  fs.writeFileSync(metadataPath, `${JSON.stringify(expectedMetadata)}\n`);

  const result = spawnSync(process.execPath, [files.verifyMetadata, metadataPath, files.sources], {
    cwd: process.cwd(),
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /verified One-KVM build provenance metadata/);
});

test('rejects modified dependency and compiler provenance', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-one-kvm-metadata-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));

  for (const [name, metadata] of [
    ['x264', { ...expectedMetadata, dependencies: { ...expectedMetadata.dependencies, x264: '0'.repeat(40) } }],
    ['gcc', { ...expectedMetadata, toolchain: { ...expectedMetadata.toolchain, gcc: '12.2.0' } }],
  ]) {
    const metadataPath = path.join(fixture, `${name}.json`);
    fs.writeFileSync(metadataPath, `${JSON.stringify(metadata)}\n`);
    const result = spawnSync(process.execPath, [files.verifyMetadata, metadataPath, files.sources], {
      cwd: process.cwd(),
      encoding: 'utf8',
    });

    assert.notEqual(result.status, 0, `${name} mutation must fail`);
    assert.match(result.stderr, new RegExp(name, 'i'));
  }
});

test('prebuilds the ARMv7 Cross image with BuildKit and disables Cross dockerfile rebuilds', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-cross-image-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const sourceDir = path.join(fixture, 'source');
  const fakeBin = path.join(fixture, 'bin');
  const capturePath = path.join(fixture, 'docker-invocation.txt');
  fs.mkdirSync(path.join(sourceDir, 'build', 'cross'), { recursive: true });
  fs.mkdirSync(fakeBin);
  fs.writeFileSync(
    path.join(sourceDir, 'Cross.toml'),
    [
      '[target.x86_64-unknown-linux-gnu]',
      'dockerfile = "build/cross/Dockerfile.x86_64"',
      '',
      '[target.armv7-unknown-linux-gnueabihf]',
      'dockerfile = "build/cross/Dockerfile.armv7"',
      '',
      '[target.aarch64-unknown-linux-gnu]',
      'dockerfile = "build/cross/Dockerfile.arm64"',
      '',
    ].join('\n'),
  );
  fs.writeFileSync(path.join(sourceDir, 'build', 'cross', 'Dockerfile.armv7'), 'FROM scratch\n');
  const fakeDocker = path.join(fakeBin, 'docker');
  fs.writeFileSync(
    fakeDocker,
    '#!/usr/bin/env bash\nset -euo pipefail\nprintf "%s\\n" "DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-}" "$@" >"$CAPTURE_PATH"\n',
  );
  fs.chmodSync(fakeDocker, 0o755);

  const image = 'ws1608-one-kvm-armv7:test-123';
  const result = spawnSync('bash', [files.prepareCrossImage, sourceDir, image], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: {
      ...process.env,
      CAPTURE_PATH: capturePath,
      PATH: `${fakeBin}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(fs.readFileSync(capturePath, 'utf8').trim().split('\n'), [
    'DOCKER_BUILDKIT=1',
    'build',
    '--platform',
    'linux/amd64',
    '--progress=plain',
    '--tag',
    image,
    '--file',
    path.join(sourceDir, 'build', 'cross', 'Dockerfile.armv7'),
    sourceDir,
  ]);
  const crossConfig = fs.readFileSync(path.join(sourceDir, 'Cross.toml'), 'utf8');
  const armv7Block = crossConfig.match(
    /\[target\.armv7-unknown-linux-gnueabihf\]([\s\S]*?)(?=\n\[|$)/,
  )?.[1];
  assert.ok(armv7Block, 'ARMv7 Cross target block must remain present');
  assert.doesNotMatch(armv7Block, /^dockerfile\s*=/m);
  assert.match(armv7Block, /^image = "ws1608-one-kvm-armv7:test-123"$/m);
  assert.match(crossConfig, /dockerfile = "build\/cross\/Dockerfile\.x86_64"/);
  assert.match(crossConfig, /dockerfile = "build\/cross\/Dockerfile\.arm64"/);
});
