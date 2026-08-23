#!/usr/bin/env node

import fs from 'node:fs';

function parseEnvironment(contents) {
  return Object.fromEntries(contents.split(/\r?\n/).filter((line) => line && !line.startsWith('#')).map((line) => {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid environment line: ${line}`);
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
}

function requireEqual(actual, expected, name) {
  if (actual !== expected) throw new Error(`${name} does not match its immutable source lock`);
}

function verify(metadata, sources) {
  requireEqual(metadata.schema, 1, 'schema');
  requireEqual(metadata.channel, 'experimental', 'channel');
  requireEqual(metadata.upstream_repository, sources.ONE_KVM_REPOSITORY, 'upstream repository');
  requireEqual(metadata.upstream_ref, sources.ONE_KVM_REF, 'upstream ref');
  requireEqual(metadata.upstream_commit, sources.ONE_KVM_COMMIT, 'upstream commit');
  requireEqual(metadata.one_kvm_version, sources.ONE_KVM_VERSION, 'One-KVM version');
  requireEqual(metadata.rust_toolchain, sources.ONE_KVM_RUST_TOOLCHAIN, 'Rust toolchain');
  requireEqual(metadata.rustc_commit, sources.ONE_KVM_RUSTC_COMMIT, 'rustc commit');
  requireEqual(metadata.pnpm_version, sources.ONE_KVM_PNPM_VERSION, 'pnpm version');
  requireEqual(metadata.source_date_epoch, Number(sources.ONE_KVM_SOURCE_DATE_EPOCH), 'source date epoch');
  requireEqual(metadata.build_container, sources.ONE_KVM_ARMV7_OCI_IMAGE, 'build container');
  requireEqual(metadata.toolchain?.gcc, sources.ONE_KVM_ARMV7_GCC_VERSION, 'gcc');
  requireEqual(metadata.toolchain?.binutils, sources.ONE_KVM_ARMV7_BINUTILS_VERSION, 'binutils');
  requireEqual(metadata.dependencies?.x264, sources.ONE_KVM_X264_COMMIT, 'x264');
  requireEqual(metadata.dependencies?.rkmpp, sources.ONE_KVM_RKMPP_COMMIT, 'rkmpp');
  requireEqual(metadata.dependencies?.rkrga, sources.ONE_KVM_RKRGA_COMMIT, 'rkrga');
  if (!new RegExp(`^${sources.ONE_KVM_VERSION.replaceAll('.', '\\.')}\\+ws1608amlenc\\.[A-Za-z0-9][A-Za-z0-9.-]{0,31}$`).test(metadata.package_version)) throw new Error('invalid package version');
  for (const name of ['patches_sha256', 'dependency_locks_sha256']) {
    if (!/^[0-9a-f]{64}$/.test(metadata[name])) throw new Error(`invalid ${name}`);
  }
  requireEqual(metadata.platform, 'WS1608/S805/Meson8b/armv7', 'platform');
  requireEqual(metadata.codec, 'h264_amlenc', 'codec');
  requireEqual(metadata.amlenc_smoke_test_default, false, 'AMLENC smoke test default');
  requireEqual(metadata.hardware_encoder_tested, false, 'hardware encoder status');
  requireEqual(metadata.stable_channel_modified, false, 'stable channel status');
  requireEqual(metadata.redistribution, 'local-test-only', 'redistribution');
}

try {
  const metadata = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const sources = parseEnvironment(fs.readFileSync(process.argv[3], 'utf8'));
  verify(metadata, sources);
  process.stdout.write('verified One-KVM build provenance metadata\n');
} catch (error) {
  process.stderr.write(`One-KVM metadata verification failed: ${error.message}\n`);
  process.exitCode = 1;
}
