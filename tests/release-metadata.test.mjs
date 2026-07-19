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
  package_sha256: 'a'.repeat(64),
  build_tag: 'ws1608-one-kvm-0.2.4-v260709-b001',
  build_number: 1,
  builder_commit: '0123456789abcdef0123456789abcdef01234567',
};

async function fixture() {
  const outputDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ws1608-release-'));
  const imageName = 'One-KVM_0.2.4-v260709-b001_Onecloud-test.burn.img';
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
  return {
    ...identity,
    package_url: 'https://example.invalid/one-kvm_0.2.4_armhf.deb',
    base_sha256: 'b'.repeat(64),
    github_run_id: '12345',
  };
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
      ...identity,
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

test('packages and verifies release assets through the shell entrypoint', async () => {
  const data = await fixture();
  const imageBytes = await fs.readFile(data.imagePath);
  await fs.writeFile(path.join(data.outputDir, 'manifest.json'), JSON.stringify({
    schema_version: 2,
    ...identity,
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
      PACKAGE_URL: expectedValues().package_url,
      PACKAGE_DIGEST: identity.package_sha256,
      BUILD_TAG: identity.build_tag,
      BUILD_NUMBER: String(identity.build_number),
      BUILDER_COMMIT: identity.builder_commit,
      GITHUB_RUN_ID: expectedValues().github_run_id,
    },
  });

  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.deepEqual(
    (await fs.readdir(data.outputDir)).sort(),
    [data.imageName, `${data.imageName}.xz`, 'manifest.json', 'SHA256SUMS', data.reportName].sort(),
  );
});
