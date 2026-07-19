#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const [, , artifactDir, expectedImageName, expectedJson] = process.argv;

function fail(message) {
  throw new Error(message);
}

function requireFile(directory, name) {
  const filePath = path.join(directory, name);
  if (!fs.statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
    fail(`missing artifact file: ${name}`);
  }
  return filePath;
}

function hashFile(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

function filesEqual(leftPath, rightPath) {
  const left = fs.openSync(leftPath, 'r');
  const right = fs.openSync(rightPath, 'r');
  const leftBuffer = Buffer.alloc(1024 * 1024);
  const rightBuffer = Buffer.alloc(1024 * 1024);
  try {
    if (fs.statSync(leftPath).size !== fs.statSync(rightPath).size) return false;
    let offset = 0;
    while (true) {
      const leftRead = fs.readSync(left, leftBuffer, 0, leftBuffer.length, offset);
      const rightRead = fs.readSync(right, rightBuffer, 0, rightBuffer.length, offset);
      if (leftRead !== rightRead) return false;
      if (leftRead === 0) return true;
      if (!leftBuffer.subarray(0, leftRead).equals(rightBuffer.subarray(0, rightRead))) {
        return false;
      }
      offset += leftRead;
    }
  } finally {
    fs.closeSync(left);
    fs.closeSync(right);
  }
}

function readChecksums(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  if (lines.at(-1) === '') lines.pop();
  if (lines.length !== 2) fail('SHA256SUMS must contain exactly two entries');
  const entries = new Map();
  for (const line of lines) {
    const match = line.match(/^([0-9a-f]{64})  (.+)$/);
    if (!match || entries.has(match[2])) fail(`invalid SHA256SUMS line: ${line}`);
    entries.set(match[2], match[1]);
  }
  return entries;
}

function decompress(inputPath, outputPath) {
  const output = fs.openSync(outputPath, 'w');
  const result = spawnSync('xz', ['-dc', inputPath], {
    stdio: ['ignore', output, 'pipe'],
  });
  fs.closeSync(output);
  if (result.status !== 0) {
    fail(`xz decompression failed: ${result.stderr.toString()}`);
  }
}

async function verify() {
  if (!artifactDir || !expectedImageName || !expectedJson) {
    fail('usage: verify-artifacts.mjs ARTIFACT_DIR EXPECTED_IMAGE_NAME EXPECTED_JSON');
  }
  const expected = JSON.parse(expectedJson);
  const imageXzName = `${expectedImageName}.xz`;
  const entries = fs.readdirSync(artifactDir);
  const required = [expectedImageName, imageXzName, 'SHA256SUMS', 'manifest.json'].sort();
  if (entries.slice().sort().join('\n') !== required.join('\n')) {
    fail(`artifact directory must contain exactly: ${required.join(', ')}; found: ${entries.join(', ')}`);
  }

  const imagePath = requireFile(artifactDir, expectedImageName);
  const imageXzPath = requireFile(artifactDir, imageXzName);
  const sums = readChecksums(requireFile(artifactDir, 'SHA256SUMS'));
  const imageHash = await hashFile(imagePath);
  const imageXzHash = await hashFile(imageXzPath);
  if (sums.get(expectedImageName) !== imageHash) fail('raw image SHA256SUMS digest mismatch');
  if (sums.get(imageXzName) !== imageXzHash) fail('compressed image SHA256SUMS digest mismatch');

  const manifest = JSON.parse(fs.readFileSync(requireFile(artifactDir, 'manifest.json'), 'utf8'));
  if (manifest.image !== expectedImageName) fail('manifest image name mismatch');
  if (manifest.image_xz !== imageXzName) fail('manifest compressed image name mismatch');
  if (manifest.image_sha256 !== imageHash) fail('manifest raw image digest mismatch');
  if (manifest.image_xz_sha256 !== imageXzHash) fail('manifest compressed image digest mismatch');
  for (const [key, value] of Object.entries(expected)) {
    if (manifest[key] !== value) fail(`manifest field mismatch: ${key}`);
  }

  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-artifact-verify-'));
  const roundTripPath = path.join(temporaryDirectory, expectedImageName);
  try {
    decompress(imageXzPath, roundTripPath);
    if (!filesEqual(imagePath, roundTripPath)) fail('xz round-trip does not match the raw image');
  } finally {
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
  console.log(`verified-artifacts ${expectedImageName}`);
}

verify().catch((error) => {
  console.error(`artifact verification failed: ${error.message}`);
  process.exitCode = 1;
});

