import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function fileMetadata(outputDir, name) {
  if (path.basename(name) !== name) throw new Error(`artifact name is not a basename: ${name}`);
  const filePath = path.join(outputDir, name);
  const stat = await fsp.stat(filePath);
  if (!stat.isFile() || stat.size === 0) throw new Error(`artifact is missing or empty: ${name}`);
  return { name, size: stat.size, sha256: await sha256File(filePath) };
}

function requireProvenance(provenance) {
  for (const key of ['package_url', 'package_sha256', 'base_sha256', 'build_tag', 'github_run_id']) {
    if (!provenance?.[key]) throw new Error(`missing provenance field: ${key}`);
  }
}

function compareField(actual, expected, key) {
  if (expected !== undefined && actual !== expected) {
    throw new Error(`${key} mismatch: expected ${expected}, found ${actual}`);
  }
}

export async function finalizeManifest({
  outputDir,
  imageName,
  compressedImageName,
  validationReportName,
  partialManifest,
  provenance,
}) {
  requireProvenance(provenance);
  const image = await fileMetadata(outputDir, imageName);
  const compressed = await fileMetadata(outputDir, compressedImageName);
  const report = await fileMetadata(outputDir, validationReportName);
  const reportJson = JSON.parse(await fsp.readFile(path.join(outputDir, validationReportName), 'utf8'));
  if (reportJson.result !== 'passed' || reportJson.hardware_boot_tested !== false) {
    throw new Error('validation report must be passed and hardware_boot_tested=false');
  }
  compareField(partialManifest.image, imageName, 'image');
  compareField(partialManifest.image_sha256, image.sha256, 'image_sha256');
  for (const key of [
    'one_kvm_version',
    'one_kvm_release',
    'package_sha256',
    'build_tag',
    'build_number',
    'builder_commit',
  ]) {
    compareField(partialManifest[key], provenance[key], key);
  }

  const manifest = {
    ...partialManifest,
    schema_version: 2,
    package_url: provenance.package_url,
    package_sha256: provenance.package_sha256,
    base_sha256: provenance.base_sha256,
    github_run_id: String(provenance.github_run_id),
    built_at: provenance.built_at ?? new Date().toISOString(),
    image: image.name,
    image_size: image.size,
    image_sha256: image.sha256,
    compressed_image: compressed.name,
    compressed_image_size: compressed.size,
    compressed_image_sha256: compressed.sha256,
    validation_report: report.name,
    validation_report_size: report.size,
    validation_report_sha256: report.sha256,
    validation: 'passed',
  };
  await fsp.writeFile(
    path.join(outputDir, 'manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
    'utf8',
  );
  return manifest;
}

async function readChecksums(outputDir, expectedNames) {
  const text = await fsp.readFile(path.join(outputDir, 'SHA256SUMS'), 'utf8');
  const entries = new Map();
  for (const line of text.trimEnd().split(/\r?\n/)) {
    const match = /^([0-9a-f]{64})  (.+)$/.exec(line);
    if (!match) throw new Error(`invalid checksum line or checksum path: ${line}`);
    if (match[2].includes('/') || match[2].includes('\\')) throw new Error(`checksum path: ${match[2]}`);
    if (entries.has(match[2])) throw new Error(`duplicate checksum: ${match[2]}`);
    entries.set(match[2], match[1]);
  }
  const expected = new Set(expectedNames);
  if (entries.size !== expected.size || [...expected].some((name) => !entries.has(name))) {
    throw new Error('SHA256SUMS does not contain exactly the release assets');
  }
  for (const [name, digest] of entries) {
    const actual = await sha256File(path.join(outputDir, name));
    if (actual !== digest) throw new Error(`checksum mismatch: ${name}`);
  }
}

async function assertArtifact(manifest, outputDir, name, sizeKey, digestKey) {
  const actual = await fileMetadata(outputDir, name);
  compareField(manifest[sizeKey], actual.size, sizeKey);
  compareField(manifest[digestKey], actual.sha256, digestKey);
}

export async function writeChecksums(outputDir, names) {
  const lines = [];
  for (const name of names) {
    const metadata = await fileMetadata(outputDir, name);
    lines.push(`${metadata.sha256}  ${name}`);
  }
  await fsp.writeFile(path.join(outputDir, 'SHA256SUMS'), `${lines.join('\n')}\n`, 'utf8');
}

export async function validateReleaseAssets({ outputDir, expected }) {
  const manifest = JSON.parse(await fsp.readFile(path.join(outputDir, 'manifest.json'), 'utf8'));
  for (const [key, value] of Object.entries(expected ?? {})) compareField(manifest[key], value, key);
  if (manifest.schema_version !== 2) throw new Error('manifest schema_version must be 2');
  if (manifest.validation !== 'passed') throw new Error('manifest validation must be passed');

  const names = [manifest.image, manifest.compressed_image, manifest.validation_report];
  for (const name of names) {
    if (path.basename(String(name)) !== name) throw new Error(`artifact name is not a basename: ${name}`);
  }
  const report = JSON.parse(await fsp.readFile(path.join(outputDir, manifest.validation_report), 'utf8'));
  if (report.result !== 'passed') throw new Error('validation report result is not passed');
  if (report.hardware_boot_tested !== false) throw new Error('validation report hardware claim is invalid');
  for (const key of [
    'one_kvm_version',
    'one_kvm_release',
    'package_sha256',
    'build_tag',
    'build_number',
    'builder_commit',
  ]) {
    compareField(report[key], manifest[key], `validation report ${key}`);
  }

  await assertArtifact(manifest, outputDir, manifest.image, 'image_size', 'image_sha256');
  await assertArtifact(manifest, outputDir, manifest.compressed_image, 'compressed_image_size', 'compressed_image_sha256');
  await assertArtifact(manifest, outputDir, manifest.validation_report, 'validation_report_size', 'validation_report_sha256');
  const allowed = new Set([...names, 'manifest.json', 'SHA256SUMS']);
  for (const entry of await fsp.readdir(outputDir)) {
    if (!allowed.has(entry)) throw new Error(`unexpected release file: ${entry}`);
  }
  await readChecksums(outputDir, [...names, 'manifest.json']);
  return true;
}
