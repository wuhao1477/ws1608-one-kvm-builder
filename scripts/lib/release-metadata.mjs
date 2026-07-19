import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';

const PROVENANCE_FIELDS = [
  'one_kvm_version',
  'one_kvm_release',
  'package_name',
  'package_url',
  'package_sha256',
  'base_release_tag',
  'base_image_name',
  'base_image_url',
  'base_sha256',
  'build_tag',
  'build_revision',
  'build_number',
  'builder_commit',
  'github_run_id',
  'github_run_attempt',
  'github_run_number',
  'amlimg_repository',
  'amlimg_commit',
];
const CORE_IDENTITY_FIELDS = [
  'one_kvm_version',
  'one_kvm_release',
  'package_sha256',
  'build_tag',
  'build_number',
  'builder_commit',
];

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function writeAtomic(filePath, text) {
  try {
    const stat = await fsp.lstat(filePath);
    if (stat.isSymbolicLink()) throw new Error(`refusing symlink: ${filePath}`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const temporary = `${filePath}.tmp-${process.pid}-${crypto.randomUUID()}`;
  try {
    await fsp.writeFile(temporary, text, { encoding: 'utf8', flag: 'wx' });
    await fsp.rename(temporary, filePath);
  } finally {
    try { await fsp.unlink(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

function assertBasename(name) {
  if (
    typeof name !== 'string'
    || !name
    || name === '.'
    || name === '..'
    || path.basename(name) !== name
    || name.includes('\\')
  ) {
    throw new Error(`artifact name is not a basename: ${name}`);
  }
}

async function fileMetadata(outputDir, name) {
  assertBasename(name);
  const filePath = path.join(outputDir, name);
  const stat = await fsp.lstat(filePath);
  if (!stat.isFile()) throw new Error(`artifact is not a regular file: ${name}`);
  if (stat.size === 0) throw new Error(`artifact is missing or empty: ${name}`);
  return { name, size: stat.size, sha256: await sha256File(filePath) };
}

function requireProvenance(provenance) {
  for (const key of PROVENANCE_FIELDS) {
    if (provenance?.[key] === undefined || provenance[key] === '') {
      throw new Error(`missing provenance field: ${key}`);
    }
  }
  for (const key of ['package_sha256', 'base_sha256']) {
    if (!/^[0-9a-f]{64}$/.test(provenance[key])) throw new Error(`invalid provenance digest: ${key}`);
  }
  for (const key of ['builder_commit', 'amlimg_commit']) {
    if (!/^[0-9a-f]{40}$/.test(provenance[key])) throw new Error(`invalid provenance commit: ${key}`);
  }
  if (!Number.isSafeInteger(provenance.build_number) || provenance.build_number < 1) {
    throw new Error('build_number must be a positive integer');
  }
  const revisions = [
    `b${String(provenance.build_number).padStart(3, '0')}`,
    `b${String(provenance.build_number).padStart(6, '0')}`,
  ];
  if (!revisions.includes(provenance.build_revision)) throw new Error('build_revision mismatch');
  if (!provenance.build_tag.endsWith(`-${provenance.build_revision}`)) {
    throw new Error('build_tag does not end with build_revision');
  }
  assertBasename(provenance.package_name);
  assertBasename(provenance.base_image_name);
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
  compareField(compressedImageName, `${imageName}.xz`, 'compressed_image');
  for (const key of CORE_IDENTITY_FIELDS) {
    compareField(partialManifest[key], provenance[key], key);
  }
  for (const key of PROVENANCE_FIELDS) {
    compareField(reportJson[key], provenance[key], `validation report ${key}`);
  }

  const manifest = {
    ...partialManifest,
    ...Object.fromEntries(PROVENANCE_FIELDS.map((key) => [key, provenance[key]])),
    schema_version: 2,
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
  await writeAtomic(path.join(outputDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

async function readChecksums(outputDir, expectedNames) {
  await fileMetadata(outputDir, 'SHA256SUMS');
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
  if (new Set(names).size !== names.length) throw new Error('duplicate checksum asset name');
  const lines = [];
  for (const name of names) {
    const metadata = await fileMetadata(outputDir, name);
    lines.push(`${metadata.sha256}  ${name}`);
  }
  await writeAtomic(path.join(outputDir, 'SHA256SUMS'), `${lines.join('\n')}\n`);
}

export async function validateReleaseAssets({ outputDir, expected }) {
  await fileMetadata(outputDir, 'manifest.json');
  const manifest = JSON.parse(await fsp.readFile(path.join(outputDir, 'manifest.json'), 'utf8'));
  for (const [key, value] of Object.entries(expected ?? {})) compareField(manifest[key], value, key);
  if (manifest.schema_version !== 2) throw new Error('manifest schema_version must be 2');
  if (manifest.validation !== 'passed') throw new Error('manifest validation must be passed');
  if (Number.isNaN(Date.parse(manifest.built_at))) throw new Error('manifest built_at is invalid');
  requireProvenance(manifest);

  const names = [manifest.image, manifest.compressed_image, manifest.validation_report];
  for (const name of names) assertBasename(name);
  const report = JSON.parse(await fsp.readFile(path.join(outputDir, manifest.validation_report), 'utf8'));
  if (report.result !== 'passed') throw new Error('validation report result is not passed');
  if (report.hardware_boot_tested !== false) throw new Error('validation report hardware claim is invalid');
  for (const key of PROVENANCE_FIELDS) {
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
