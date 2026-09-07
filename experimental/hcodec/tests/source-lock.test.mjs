import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const validator = 'experimental/hcodec/scripts/verify-source-locks.mjs';
const sources = 'experimental/hcodec/config/sources.env';

function validEnvironment() {
  return [
    'BASE_RELEASE_TAG=base-20260804-consolefix',
    'BASE_IMAGE_SHA256=0edb5f729be17bff40ee2949a715d5604f4c0a873d4a2deb9a294745af541d3a',
    'ARMBIAN_BUILD_REPOSITORY=https://github.com/armbian/build.git',
    'ARMBIAN_BUILD_REF=fa7a7b2294d9e760a77630950afd460b7a0b2a26',
    'ARMBIAN_BUILD_COMMIT=fa7a7b2294d9e760a77630950afd460b7a0b2a26',
    'ARMBIAN_BUILD_ARCHIVE_URL=https://codeload.github.com/armbian/build/tar.gz/fa7a7b2294d9e760a77630950afd460b7a0b2a26',
    'ARMBIAN_BUILD_ARCHIVE_SHA256=64dfd6d6438bfb145ec1c97142c231d4eb830aed2aaaed01b610086523b15028',
    'ARMBIAN_VERSION=26.8.0-trunk.413',
    'ARMBIAN_DRIVERS_HASH=398d1f81_253338bb',
    'ARMBIAN_PATCHES_HASH=ca1a33f8b63ed656',
    'ARMBIAN_CONFIG_HASH=8bd94fb6ccbfc1ae',
    'ARMBIAN_CONFIG_HOOK_HASH=23bf009b6df9a4f7',
    'ARMBIAN_VARIABLES_SHA256=a13228369c8c392d623aef1f32ad559f84572c8c9c2b16fd218b094b9421c846',
    'ARMBIAN_FRAMEWORK_BASH_HASH=5272f33f0e8e0d8b',
    'LINUX_REPOSITORY=https://github.com/torvalds/linux.git',
    'LINUX_REF=v6.12.28',
    'LINUX_COMMIT=f08cdc6cc92e3d23a05745f0f12f8caa348a27b4',
    'LINUX_ARCHIVE_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.28.tar.xz',
    'LINUX_ARCHIVE_SHA256=e8a099182562aecff781de72ce769461e706d97af42d740dff20eb450dd5771e',
    'KERNEL_VERSION=6.12.28',
    'KERNEL_RELEASE=6.12.28-current-meson',
    'KERNEL_CONFIG_SHA256=4fbdf08f40fe06be1339f7bcc326c71177f81225302801127b4d7371aca24ea9',
    'BASE_DTB_SHA256=898900ea47a5b8963cb9c5af023cfa6ab405fa2c4954dd1b06585591dc59aa75',
    'BASE_UIMAGE_SHA256=38bdbe554e05c75704bfbbe1a63ab3e54ee8bc4c8211405182cbd932b13cab3e',
    'BASE_BOOT_CMD_SHA256=7c85b7a97c143357c4639551451c4e46710eee260e758b1296f3b65717a75efd',
    'BASE_ARMBIAN_ENV_SHA256=e3492dfbc6f0ffa79d5b002b68c38558f1cb1b22439e5c56559fc4b2d1e54f03',
    'UIMAGE_LOAD_ADDRESS=0x00208000',
    'UIMAGE_ENTRY_POINT=0x00208000',
    'UBOOT_LOAD_ADDRESS=0x20800000',
    'MODULE_SIGNING=disabled',
    'TOOLCHAIN_CONTAINER=ubuntu:24.04@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316',
    'FIRMWARE_REPOSITORY=https://github.com/hardkernel/linux.git',
    'FIRMWARE_COMMIT=5aed95d35d252cafc75ce613a3a0052285662de2',
    'FIRMWARE_ARCHIVE_URL=https://codeload.github.com/hardkernel/linux/tar.gz/5aed95d35d252cafc75ce613a3a0052285662de2',
    'FIRMWARE_ARCHIVE_SHA256=0c3bbbf7d8ff9f3f687502b6f36753b9bb4e13e31ea8c85ee498857b4d581dd5',
    'FIRMWARE_REDISTRIBUTION=unverified',
    'FIRMWARE_INPUT_PATH=drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h',
    'FIRMWARE_WORD_COUNT=2384',
    'FIRMWARE_OUTPUT_SIZE=9536',
    'FIRMWARE_OUTPUT_SHA256=2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368',
    'RESEARCH_ARCHIVE_SHA256=4422aa4c8d9f3f18cc6220ec3c0da056ed5979fdddeaad1b6b09166edf80e0a6',
    'CANDIDATE_EXTRAARGS=cma=128M',
    'BOARD=onecloud',
    'ARCH=arm',
    '',
  ].join('\n');
}

test('accepts the complete immutable HCODEC source lock', () => {
  const result = spawnSync(process.execPath, [validator, sources], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /verified HCODEC source locks/);
});

test('rejects a missing archive digest and duplicate key', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-source-lock-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const invalid = path.join(directory, 'sources.env');
  const contents = validEnvironment()
    .replace(/^LINUX_ARCHIVE_SHA256=.*\n/m, '')
    .concat('KERNEL_VERSION=6.12.28\n');
  fs.writeFileSync(invalid, contents);

  const result = spawnSync(process.execPath, [validator, invalid], { encoding: 'utf8' });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /duplicate key KERNEL_VERSION|missing LINUX_ARCHIVE_SHA256/);
});

test('rejects moving refs and unpinned Docker images', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-source-lock-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const invalid = path.join(directory, 'sources.env');
  const contents = validEnvironment()
    .replace(/^ARMBIAN_BUILD_REF=.*$/m, 'ARMBIAN_BUILD_REF=main')
    .replace(/^TOOLCHAIN_CONTAINER=.*$/m, 'TOOLCHAIN_CONTAINER=ubuntu:24.04');
  fs.writeFileSync(invalid, contents);

  const result = spawnSync(process.execPath, [validator, invalid], { encoding: 'utf8' });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ARMBIAN_BUILD_REF|TOOLCHAIN_CONTAINER/);
});
