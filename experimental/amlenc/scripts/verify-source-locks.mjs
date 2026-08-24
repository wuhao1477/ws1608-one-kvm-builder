#!/usr/bin/env node

import fs from 'node:fs';

const sourceNames = ['LINUX', 'LIBENCODER', 'ONE_KVM', 'AMLENC'];
const commitPattern = /^[0-9a-f]{40}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;
const boardEvidence = {
  ONECLOUD_DTS_REPOSITORY: 'https://github.com/coolsnowwolf/lede.git',
  ONECLOUD_DTS_COMMIT: 'f7fd86eaa58c29fed97da04ab219c74a835a9358',
  ONECLOUD_DTS_PATH: 'target/linux/amlogic/files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts',
  ONECLOUD_DTS_SHA256: '2728716388bb0c023cf380780b7fee7cf3d361ee3144c722e55f22234cae548f',
  ONECLOUD_UBOOT_REPOSITORY: 'https://github.com/hzyitc/u-boot.git',
  ONECLOUD_UBOOT_COMMIT: '0038d741ed1c77a77570c3a6bf88fe6189c11733',
};

function parseEnvironment(contents) {
  const values = new Map();
  for (const [index, rawLine] of contents.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^([A-Z][A-Z0-9_]*)=(\S+)$/);
    if (!match) throw new Error(`invalid line ${index + 1}`);
    if (values.has(match[1])) throw new Error(`duplicate key ${match[1]}`);
    values.set(match[1], match[2]);
  }
  return values;
}

function requireValue(values, key) {
  const value = values.get(key);
  if (!value) throw new Error(`missing ${key}`);
  return value;
}

function verifySource(values, name) {
  const repository = requireValue(values, `${name}_REPOSITORY`);
  const commit = requireValue(values, `${name}_COMMIT`);
  const archiveUrl = requireValue(values, `${name}_ARCHIVE_URL`);
  const archiveSha256 = requireValue(values, `${name}_ARCHIVE_SHA256`);
  requireValue(values, `${name}_REF`);

  if (!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\.git$/.test(repository)) {
    throw new Error(`${name}_REPOSITORY must be a GitHub HTTPS URL`);
  }
  if (!commitPattern.test(commit)) throw new Error(`${name}_COMMIT must be 40 lowercase hex characters`);
  if (!sha256Pattern.test(archiveSha256)) throw new Error(`${name}_ARCHIVE_SHA256 must be 64 lowercase hex characters`);
  if (!archiveUrl.startsWith('https://codeload.github.com/') || !archiveUrl.endsWith(`/tar.gz/${commit}`)) {
    throw new Error(`${name}_ARCHIVE_URL must end with the pinned commit`);
  }
}

function verifyBoardEvidence(values) {
  for (const [key, expected] of Object.entries(boardEvidence)) {
    if (requireValue(values, key) !== expected) throw new Error(`${key} does not match reviewed board evidence`);
  }
  if (!commitPattern.test(requireValue(values, 'ONECLOUD_DTS_COMMIT'))) throw new Error('invalid OneCloud DTS commit');
  if (!commitPattern.test(requireValue(values, 'ONECLOUD_UBOOT_COMMIT'))) throw new Error('invalid OneCloud U-Boot commit');
  if (!sha256Pattern.test(requireValue(values, 'ONECLOUD_DTS_SHA256'))) throw new Error('invalid OneCloud DTS digest');
  if (requireValue(values, 'ONECLOUD_DTS_PATH').split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new Error('ONECLOUD_DTS_PATH must be a safe relative path');
  }
}

function main() {
  const filePath = process.argv[2] ?? 'experimental/amlenc/config/sources.env';
  const values = parseEnvironment(fs.readFileSync(filePath, 'utf8'));
  for (const name of sourceNames) verifySource(values, name);
  verifyBoardEvidence(values);
  requireValue(values, 'ONE_KVM_VERSION');
  requireValue(values, 'KERNEL_VERSION');
  requireValue(values, 'DEBIAN_SUITE');
  requireValue(values, 'DEBIAN_ARCH');
  for (const key of ['BULLSEYE_ARMV7_OCI_IMAGE', 'IMAGE_TOOLS_ARM64_OCI_IMAGE']) {
    const image = requireValue(values, key);
    if (!/^debian:[a-z0-9.-]+@sha256:[0-9a-f]{64}$/.test(image)) {
      throw new Error(`${key} must be a digest-pinned Debian OCI image`);
    }
  }
  const armv7Image = requireValue(values, 'ONE_KVM_ARMV7_OCI_IMAGE');
  if (!/^debian:11@sha256:[0-9a-f]{64}$/.test(armv7Image)) {
    throw new Error('ONE_KVM_ARMV7_OCI_IMAGE must be a digest-pinned Debian 11 image');
  }
  for (const key of ['ONE_KVM_X264_COMMIT', 'ONE_KVM_LIBVPX_COMMIT', 'ONE_KVM_X265_COMMIT', 'ONE_KVM_RKMPP_COMMIT', 'ONE_KVM_RKRGA_COMMIT', 'ONE_KVM_RUSTC_COMMIT']) {
    if (!commitPattern.test(requireValue(values, key))) throw new Error(`${key} must be a pinned commit`);
  }
  for (const key of ['ONE_KVM_ARMV7_GCC_VERSION', 'ONE_KVM_ARMV7_BINUTILS_VERSION', 'ONE_KVM_RUST_TOOLCHAIN', 'ONE_KVM_PNPM_VERSION']) {
    if (!/^[0-9]+\.[0-9]+(?:\.[0-9]+)?$/.test(requireValue(values, key))) throw new Error(`${key} must be a version`);
  }
  if (!/^[0-9]{10}$/.test(requireValue(values, 'ONE_KVM_SOURCE_DATE_EPOCH'))) {
    throw new Error('ONE_KVM_SOURCE_DATE_EPOCH must be a ten-digit epoch');
  }
  process.stdout.write(`verified ${sourceNames.length} immutable source locks\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`source lock verification failed: ${error.message}\n`);
  process.exitCode = 1;
}
