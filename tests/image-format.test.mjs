import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

import {
  amlCrc32,
  parseAmlogicImage,
  parseSparseHeader,
} from '../scripts/lib/image-format.mjs';

test('parses an Android sparse header and rejects a bad magic', () => {
  const header = Buffer.alloc(28);
  header.writeUInt32LE(0xed26ff3a, 0);
  header.writeUInt16LE(1, 4);
  header.writeUInt16LE(0, 6);
  header.writeUInt16LE(28, 8);
  header.writeUInt16LE(12, 10);
  header.writeUInt32LE(4096, 12);
  header.writeUInt32LE(10, 16);
  header.writeUInt32LE(2, 20);

  assert.deepEqual(parseSparseHeader(header), {
    majorVersion: 1,
    fileHeaderSize: 28,
    chunkHeaderSize: 12,
    blockSize: 4096,
    totalBlocks: 10,
    totalChunks: 2,
  });
  assert.throws(() => parseSparseHeader(Buffer.alloc(28)), /sparse magic/);
});

test('parses Amlogic v2 items and validates the container CRC', () => {
  const image = Buffer.alloc(64 + 576);
  image.writeUInt32LE(0, 0);
  image.writeUInt32LE(2, 4);
  image.writeUInt32LE(0x27b51956, 8);
  image.writeBigUInt64LE(BigInt(image.length), 12);
  image.writeUInt32LE(4, 20);
  image.writeUInt32LE(1, 24);
  image.writeUInt32LE(0, 64);
  image.writeUInt32LE(0, 68);
  image.writeBigUInt64LE(0n, 72);
  image.writeBigUInt64LE(BigInt(image.length), 80);
  image.writeBigUInt64LE(0n, 88);
  image.write('PARTITION', 96, 'ascii');
  image.write('rootfs', 352, 'ascii');
  const crc = amlCrc32(image.subarray(4));
  image.writeUInt32LE(crc, 0);

  const parsed = parseAmlogicImage(image);
  assert.equal(parsed.version, 2);
  assert.equal(parsed.items.length, 1);
  assert.equal(parsed.items[0].type, 'PARTITION');
  assert.equal(parsed.items[0].name, 'rootfs');
  assert.equal(parsed.crcValid, true);
  image[100] ^= 1;
  assert.equal(parseAmlogicImage(image).crcValid, false);
});

test('round-trips sparse data without changing non-zero blocks', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-sparse-'));
  const rawPath = path.join(directory, 'input.raw');
  const sparsePath = path.join(directory, 'image.sparse');
  const roundTripPath = path.join(directory, 'roundtrip.raw');
  const raw = Buffer.alloc(4 * 4096);
  raw.fill(0x5a, 4096, 8192);
  raw.fill(0xa5, 3 * 4096, 4 * 4096);
  fs.writeFileSync(rawPath, raw);

  const rawToSparse = spawnSync(process.execPath, [
    path.resolve('scripts/raw-to-sparse.mjs'), rawPath, sparsePath,
  ], { encoding: 'utf8' });
  assert.equal(rawToSparse.status, 0, rawToSparse.stderr);
  const sparseToRaw = spawnSync(process.execPath, [
    path.resolve('scripts/sparse-to-raw.mjs'), sparsePath, roundTripPath,
  ], { encoding: 'utf8' });
  assert.equal(sparseToRaw.status, 0, sparseToRaw.stderr);
  assert.deepEqual(fs.readFileSync(roundTripPath), raw);
});
