#!/usr/bin/env node

import fs from 'node:fs';

const commit = /^[0-9a-f]{40}$/;
const sha256 = /^[0-9a-f]{64}$/;

function parse(contents) {
  const values = new Map();
  for (const [index, raw] of contents.split(/\r?\n/).entries()) {
    const line = raw.trim();
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

function requireSha(values, key) {
  if (!sha256.test(requireValue(values, key))) throw new Error(`${key} must be SHA-256`);
}

function requireCommit(values, key) {
  if (!commit.test(requireValue(values, key))) throw new Error(`${key} must be a full commit`);
}

function requireInteger(values, key, expected) {
  const value = requireValue(values, key);
  if (!/^\d+$/.test(value) || Number(value) !== expected) {
    throw new Error(`${key} must equal ${expected}`);
  }
}

function verify(values) {
  for (const key of ['BASE_IMAGE_SHA256', 'ARMBIAN_BUILD_ARCHIVE_SHA256', 'LINUX_ARCHIVE_SHA256',
    'KERNEL_CONFIG_SHA256', 'BASE_DTB_SHA256', 'BASE_UIMAGE_SHA256', 'BASE_BOOT_CMD_SHA256',
    'BASE_ARMBIAN_ENV_SHA256', 'FIRMWARE_ARCHIVE_SHA256', 'RESEARCH_ARCHIVE_SHA256',
    'ARMBIAN_VARIABLES_SHA256']) requireSha(values, key);
  for (const key of ['ARMBIAN_BUILD_REF', 'ARMBIAN_BUILD_COMMIT', 'LINUX_COMMIT', 'FIRMWARE_COMMIT']) {
    requireCommit(values, key);
  }
  if (requireValue(values, 'ARMBIAN_BUILD_REF') !== requireValue(values, 'ARMBIAN_BUILD_COMMIT')) {
    throw new Error('ARMBIAN_BUILD_REF must equal ARMBIAN_BUILD_COMMIT');
  }
  if (requireValue(values, 'LINUX_REF') !== 'v6.12.28') throw new Error('LINUX_REF must be v6.12.28');
  if (requireValue(values, 'KERNEL_VERSION') !== '6.12.28') throw new Error('KERNEL_VERSION mismatch');
  if (requireValue(values, 'KERNEL_RELEASE') !== '6.12.28-current-meson') throw new Error('KERNEL_RELEASE mismatch');
  if (requireValue(values, 'TOOLCHAIN_CONTAINER') !==
    'ubuntu:24.04@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316') {
    throw new Error('TOOLCHAIN_CONTAINER must be digest-pinned');
  }
  if (!requireValue(values, 'ARMBIAN_BUILD_ARCHIVE_URL').endsWith(`/${requireValue(values, 'ARMBIAN_BUILD_COMMIT')}`)) {
    throw new Error('ARMBIAN_BUILD_ARCHIVE_URL must end with the commit');
  }
  if (requireValue(values, 'LINUX_ARCHIVE_URL') !==
    'https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.28.tar.xz') {
    throw new Error('LINUX_ARCHIVE_URL must use kernel.org 6.12.28');
  }
  if (!requireValue(values, 'FIRMWARE_ARCHIVE_URL').endsWith(`/${requireValue(values, 'FIRMWARE_COMMIT')}`)) {
    throw new Error('FIRMWARE_ARCHIVE_URL must end with the commit');
  }
  if (requireValue(values, 'FIRMWARE_INPUT_PATH') !==
      'drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h') {
    throw new Error('FIRMWARE_INPUT_PATH mismatch');
  }
  requireInteger(values, 'FIRMWARE_WORD_COUNT', 2384);
  requireInteger(values, 'FIRMWARE_OUTPUT_SIZE', 9536);
  if (requireValue(values, 'FIRMWARE_OUTPUT_SHA256') !==
      '2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368') {
    throw new Error('FIRMWARE_OUTPUT_SHA256 mismatch');
  }
  for (const key of ['UIMAGE_LOAD_ADDRESS', 'UIMAGE_ENTRY_POINT']) {
    if (requireValue(values, key) !== '0x00208000') throw new Error(`${key} mismatch`);
  }
  if (requireValue(values, 'UBOOT_LOAD_ADDRESS') !== '0x20800000') throw new Error('UBOOT_LOAD_ADDRESS mismatch');
  if (requireValue(values, 'MODULE_SIGNING') !== 'disabled') throw new Error('MODULE_SIGNING mismatch');
  if (requireValue(values, 'FIRMWARE_REDISTRIBUTION') !== 'unverified') throw new Error('firmware policy mismatch');
  if (requireValue(values, 'CANDIDATE_EXTRAARGS') !== 'cma=128M') throw new Error('CANDIDATE_EXTRAARGS mismatch');
  if (requireValue(values, 'BOARD') !== 'onecloud' || requireValue(values, 'ARCH') !== 'arm') {
    throw new Error('board architecture mismatch');
  }
  for (const key of ['BASE_RELEASE_TAG', 'ARMBIAN_BUILD_REPOSITORY', 'ARMBIAN_VERSION',
    'ARMBIAN_DRIVERS_HASH', 'ARMBIAN_PATCHES_HASH', 'ARMBIAN_CONFIG_HASH',
    'ARMBIAN_CONFIG_HOOK_HASH', 'ARMBIAN_FRAMEWORK_BASH_HASH', 'LINUX_REPOSITORY',
    'FIRMWARE_REPOSITORY']) requireValue(values, key);
}

try {
  const file = process.argv[2] ?? 'experimental/hcodec/config/sources.env';
  verify(parse(fs.readFileSync(file, 'utf8')));
  process.stdout.write('verified HCODEC source locks\n');
} catch (error) {
  process.stderr.write(`HCODEC source lock failed: ${error.message}\n`);
  process.exitCode = 1;
}
