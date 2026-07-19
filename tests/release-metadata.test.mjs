import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  finalizeManifest,
  validateReleaseAssets,
  writeChecksums,
} from '../scripts/lib/release-metadata.mjs';

const identity = {
  board: 'WS1608 / OneCloud',
  base: 'Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test',
  kernel: '6.12.28-current-meson',
  one_kvm_version: '0.2.4',
  one_kvm_release: 'v260709',
  package_name: 'one-kvm_0.2.4_armhf.deb',
  package_url: 'https://example.invalid/one-kvm_0.2.4_armhf.deb',
  package_sha256: 'a'.repeat(64),
  base_release_tag: 'base-20260719',
  base_image_name: 'Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test.burn.img.xz',
  base_image_url: 'https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/download/base-20260719/Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test.burn.img.xz',
  base_sha256: 'f0bde03edd12022db41a53c546b1b16b7e49ddecbd39121f3e8c0086f700de82',
  build_tag: 'ws1608-one-kvm-0.2.4-v260709-b001',
  build_revision: 'b001',
  build_number: 1,
  builder_commit: '0123456789abcdef0123456789abcdef01234567',
  github_run_id: '12345',
  github_run_attempt: '1',
  github_run_number: '12',
  amlimg_repository: 'https://github.com/rmoyulong/AmlImg.git',
  amlimg_commit: '311cd4b892023bcb3cf6661698f5ab685e34a7f8',
};

function partialIdentity() {
  return Object.fromEntries([
    'board',
    'base',
    'kernel',
    'one_kvm_version',
    'one_kvm_release',
    'package_sha256',
    'build_tag',
    'build_number',
    'builder_commit',
  ].map((key) => [key, identity[key]]));
}

async function fixture() {
  const outputDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ws1608-release-'));
  const imageName = 'One-KVM_0.2.4-v260709-b001_Onecloud_trixie_6.12.28_HDMI-test.burn.img';
  const reportName = 'validation-report.json';
  const imagePath = path.join(outputDir, imageName);
  const reportPath = path.join(outputDir, reportName);
  await fs.writeFile(imagePath, Buffer.from('image bytes\n'));
  await fs.writeFile(reportPath, JSON.stringify({
    schema_version: 1,
    result: 'passed',
    hardware_boot_tested: false,
    ...identity,
  }));
  return { outputDir, imageName, reportName, imagePath, reportPath };
}

function expectedValues() {
  return { ...identity };
}

async function prepareRelease() {
  const data = await fixture();
  const compressedName = `${data.imageName}.xz`;
  await fs.writeFile(path.join(data.outputDir, compressedName), Buffer.from('compressed bytes\n'));
  const manifest = await finalizeManifest({
    outputDir: data.outputDir,
    imageName: data.imageName,
    compressedImageName: compressedName,
    validationReportName: data.reportName,
    partialManifest: {
      schema_version: 2,
      ...partialIdentity(),
      image: data.imageName,
      image_sha256: crypto.createHash('sha256').update('image bytes\n').digest('hex'),
    },
    provenance: expectedValues(),
  });
  await writeChecksums(data.outputDir, [
    data.imageName,
    compressedName,
    'manifest.json',
    data.reportName,
  ]);
  return { ...data, compressedName, manifest };
}

test('finalizes and validates a complete release asset set', async () => {
  const data = await prepareRelease();
  const result = await validateReleaseAssets({
    outputDir: data.outputDir,
    expected: expectedValues(),
  });

  assert.equal(result, true);
  assert.equal(data.manifest.validation, 'passed');
  assert.equal(data.manifest.image, data.imageName);
  assert.equal(data.manifest.compressed_image, data.compressedName);
  assert.equal(data.manifest.amlimg_commit, identity.amlimg_commit);
  assert.equal(data.manifest.github_run_attempt, identity.github_run_attempt);
});

test('rejects a modified image even when the old manifest remains', async () => {
  const data = await prepareRelease();
  await fs.appendFile(data.imagePath, 'tampered');

  await assert.rejects(
    validateReleaseAssets({ outputDir: data.outputDir, expected: expectedValues() }),
    /image_(size|sha256) mismatch/,
  );
});

test('rejects a failed validation report and unexpected release files', async () => {
  const data = await prepareRelease();
  const report = JSON.parse(await fs.readFile(data.reportPath, 'utf8'));
  report.result = 'failed';
  await fs.writeFile(data.reportPath, JSON.stringify(report));
  await assert.rejects(
    validateReleaseAssets({ outputDir: data.outputDir, expected: expectedValues() }),
    /validation report result/,
  );

  const clean = await prepareRelease();
  await fs.writeFile(path.join(clean.outputDir, 'unexpected.bin'), 'unexpected');
  await assert.rejects(
    validateReleaseAssets({ outputDir: clean.outputDir, expected: expectedValues() }),
    /unexpected release file/,
  );
});

test('rejects checksums containing paths', async () => {
  const data = await prepareRelease();
  await fs.writeFile(
    path.join(data.outputDir, 'SHA256SUMS'),
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  nested/image.img\n',
  );
  await assert.rejects(
    validateReleaseAssets({ outputDir: data.outputDir, expected: expectedValues() }),
    /checksum path/,
  );
});

test('rejects path-bearing artifact names before reading them', async () => {
  const data = await prepareRelease();
  const manifestPath = path.join(data.outputDir, 'manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  manifest.validation_report = '../validation-report.json';
  await fs.writeFile(manifestPath, JSON.stringify(manifest));

  await assert.rejects(
    validateReleaseAssets({ outputDir: data.outputDir, expected: expectedValues() }),
    /artifact name is not a basename/,
  );
});

test('rejects release assets that are symbolic links', async () => {
  const data = await prepareRelease();
  const compressedPath = path.join(data.outputDir, data.compressedName);
  const outsidePath = path.join(os.tmpdir(), `ws1608-outside-${crypto.randomUUID()}.xz`);
  await fs.copyFile(compressedPath, outsidePath);
  await fs.unlink(compressedPath);
  await fs.symlink(outsidePath, compressedPath);

  await assert.rejects(
    validateReleaseAssets({ outputDir: data.outputDir, expected: expectedValues() }),
    /artifact is not a regular file/,
  );
});

test('rejects path-bearing image names before creating compressed output', async () => {
  const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'ws1608-path-'));
  const outputDir = path.join(parent, 'output');
  const imagePath = path.join(parent, 'victim');
  const compressedPath = `${imagePath}.xz`;
  await fs.mkdir(outputDir);
  await fs.writeFile(imagePath, 'outside image');
  await fs.writeFile(path.join(outputDir, 'validation-report.json'), '{}');

  const result = spawnSync('bash', ['scripts/package-release.sh'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: {
      ...process.env,
      OUTPUT_DIR: outputDir,
      IMAGE_NAME: '../victim',
    },
  });

  assert.notEqual(result.status, 0);
  await assert.rejects(fs.access(compressedPath));
});

test('packages and verifies release assets through the shell entrypoint', async () => {
  const data = await fixture();
  const imageBytes = await fs.readFile(data.imagePath);
  await fs.writeFile(path.join(data.outputDir, 'manifest.json'), JSON.stringify({
    schema_version: 2,
    ...partialIdentity(),
    image: data.imageName,
    image_size: imageBytes.length,
    image_sha256: crypto.createHash('sha256').update(imageBytes).digest('hex'),
  }));
  const result = spawnSync('bash', ['scripts/package-release.sh'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: {
      ...process.env,
      OUTPUT_DIR: data.outputDir,
      IMAGE_NAME: data.imageName,
      ONE_KVM_VERSION: identity.one_kvm_version,
      UPSTREAM_TAG: identity.one_kvm_release,
      PACKAGE_NAME: identity.package_name,
      PACKAGE_URL: expectedValues().package_url,
      PACKAGE_DIGEST: identity.package_sha256,
      BASE_RELEASE_TAG: identity.base_release_tag,
      BASE_IMAGE_NAME: identity.base_image_name,
      BASE_IMAGE_URL: identity.base_image_url,
      BASE_IMAGE_SHA256: identity.base_sha256,
      BUILD_TAG: identity.build_tag,
      BUILD_REVISION: identity.build_revision,
      BUILD_NUMBER: String(identity.build_number),
      BUILDER_COMMIT: identity.builder_commit,
      GITHUB_RUN_ID: expectedValues().github_run_id,
      GITHUB_RUN_ATTEMPT: identity.github_run_attempt,
      GITHUB_RUN_NUMBER: identity.github_run_number,
      AMLIMG_REPOSITORY: identity.amlimg_repository,
      AMLIMG_COMMIT: identity.amlimg_commit,
    },
  });

  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.deepEqual(
    (await fs.readdir(data.outputDir)).sort(),
    [data.imageName, `${data.imageName}.xz`, 'manifest.json', 'SHA256SUMS', data.reportName].sort(),
  );
});
