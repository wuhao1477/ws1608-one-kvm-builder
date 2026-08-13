#!/usr/bin/env node

import fs from 'node:fs';

const sourceNames = ['LINUX', 'LIBENCODER', 'ONE_KVM', 'AMLENC'];
const commitPattern = /^[0-9a-f]{40}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;

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

function main() {
  const filePath = process.argv[2] ?? 'experimental/amlenc/config/sources.env';
  const values = parseEnvironment(fs.readFileSync(filePath, 'utf8'));
  for (const name of sourceNames) verifySource(values, name);
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
  process.stdout.write(`verified ${sourceNames.length} immutable source locks\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`source lock verification failed: ${error.message}\n`);
  process.exitCode = 1;
}
