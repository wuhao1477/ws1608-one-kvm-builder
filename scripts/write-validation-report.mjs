import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const outputPath = process.argv[2];
if (!outputPath) throw new Error('validation report path is required');

function env(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function writeAtomic(filePath, text) {
  try {
    if (fs.lstatSync(filePath).isSymbolicLink()) throw new Error(`refusing symlink: ${filePath}`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const temporary = path.join(path.dirname(filePath), `.${path.basename(filePath)}.tmp-${process.pid}-${crypto.randomUUID()}`);
  try {
    fs.writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx' });
    fs.renameSync(temporary, filePath);
  } finally {
    try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

const report = {
  schema_version: 1,
  result: 'passed',
  scope: 'hosted-runner-image-validation',
  hardware_boot_tested: false,
  one_kvm_version: env('ONE_KVM_VERSION'),
  one_kvm_release: env('UPSTREAM_TAG'),
  package_name: env('PACKAGE_NAME'),
  package_url: env('PACKAGE_URL'),
  package_sha256: env('PACKAGE_DIGEST'),
  base_release_tag: env('BASE_RELEASE_TAG'),
  base_image_name: env('BASE_IMAGE_NAME'),
  base_image_url: env('BASE_IMAGE_URL'),
  base_sha256: env('BASE_IMAGE_SHA256'),
  build_tag: env('BUILD_TAG'),
  build_revision: env('BUILD_REVISION'),
  build_number: Number(env('BUILD_NUMBER')),
  builder_commit: env('BUILDER_COMMIT'),
  github_run_id: env('GITHUB_RUN_ID'),
  github_run_attempt: env('GITHUB_RUN_ATTEMPT'),
  github_run_number: env('GITHUB_RUN_NUMBER'),
  amlimg_repository: env('AMLIMG_REPOSITORY'),
  amlimg_commit: env('AMLIMG_COMMIT'),
  onecloud_source_repository: env('ONECLOUD_SOURCE_REPOSITORY'),
  onecloud_source_commit: env('ONECLOUD_SOURCE_COMMIT'),
  onecloud_board: env('ONECLOUD_BOARD'),
  onecloud_branch: env('ONECLOUD_BRANCH'),
  onecloud_hdmi_patch_path: env('ONECLOUD_HDMI_PATCH_PATH'),
  onecloud_hdmi_patch_sha256: env('ONECLOUD_HDMI_PATCH_SHA256'),
  onecloud_uboot_repository: env('ONECLOUD_UBOOT_REPOSITORY'),
  onecloud_uboot_release: env('ONECLOUD_UBOOT_RELEASE'),
  onecloud_uboot_sha256: env('ONECLOUD_UBOOT_SHA256'),
  checks: [
    'Amlogic container unpack and CRC',
    'boot FAT and effective Linux console arguments',
    'Amlogic commands and unchanged non-rootfs partitions',
    'partition VERIFY SHA-1 values',
    'sparse round-trip and ext4 consistency',
    'One-KVM armhf package and ARM ELF binary',
    'systemd service and WS1608 OTG configuration',
    'image release metadata and build-only file removal',
  ],
};

writeAtomic(outputPath, `${JSON.stringify(report, null, 2)}\n`);
