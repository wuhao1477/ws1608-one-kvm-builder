import fs from 'node:fs';
import path from 'node:path';

import { finalizeManifest, writeChecksums } from './lib/release-metadata.mjs';

function env(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const outputDir = process.argv[2];
if (!outputDir) throw new Error('output directory is required');
const imageName = env('IMAGE_NAME');
const compressedImageName = `${imageName}.xz`;
const validationReportName = process.env.VALIDATION_REPORT_NAME ?? 'validation-report.json';
const partialManifest = JSON.parse(fs.readFileSync(path.join(outputDir, 'manifest.json'), 'utf8'));

await finalizeManifest({
  outputDir,
  imageName,
  compressedImageName,
  validationReportName,
  partialManifest,
  provenance: {
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
    built_at: process.env.BUILT_AT,
  },
});
await writeChecksums(outputDir, [
  imageName,
  compressedImageName,
  'manifest.json',
  validationReportName,
]);
