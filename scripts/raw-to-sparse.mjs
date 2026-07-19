import fs from 'node:fs';

const [, , inputPath, outputPath] = process.argv;
if (!inputPath || !outputPath) {
  throw new Error('usage: raw-to-sparse.mjs input.raw output.sparse');
}

const blockSize = 4096;
const maxRawBlocks = Math.floor((2 * 1024 * 1024 - 12) / blockSize);
const input = fs.openSync(inputPath, 'r');
const output = fs.openSync(outputPath, 'w');
const rawBlocks = [];
let chunks = 0;
try {
  const stat = fs.fstatSync(input);
  if (stat.size % blockSize !== 0) throw new Error('raw size is not 4096-byte aligned');
  const totalBlocks = stat.size / blockSize;
  const header = Buffer.alloc(28);
  header.writeUInt32LE(0xed26ff3a, 0);
  header.writeUInt16LE(1, 4);
  header.writeUInt16LE(0, 6);
  header.writeUInt16LE(28, 8);
  header.writeUInt16LE(12, 10);
  header.writeUInt32LE(blockSize, 12);
  header.writeUInt32LE(totalBlocks, 16);
  fs.writeSync(output, header);

  const block = Buffer.alloc(blockSize);
  let zeroBlocks = 0;
  let position = 0;
  while (position < stat.size) {
    const read = fs.readSync(input, block, 0, blockSize, position);
    if (read !== blockSize) throw new Error(`short read at ${position}`);
    if (isZero(block)) {
      flushRaw();
      zeroBlocks += 1;
    } else {
      if (zeroBlocks > 0) {
        writeDontCare(zeroBlocks);
        zeroBlocks = 0;
      }
      rawBlocks.push(Buffer.from(block));
      if (rawBlocks.length === maxRawBlocks) flushRaw();
    }
    position += blockSize;
  }
  flushRaw();
  if (zeroBlocks > 0) writeDontCare(zeroBlocks);
  const count = Buffer.alloc(4);
  count.writeUInt32LE(chunks, 0);
  fs.writeSync(output, count, 0, 4, 20);
} finally {
  fs.closeSync(input);
  fs.closeSync(output);
}

function isZero(buffer) {
  for (const byte of buffer) if (byte !== 0) return false;
  return true;
}

function flushRaw() {
  if (rawBlocks.length === 0) return;
  const data = Buffer.concat(rawBlocks);
  const chunk = Buffer.alloc(12);
  chunk.writeUInt16LE(0xcac1, 0);
  chunk.writeUInt32LE(rawBlocks.length, 4);
  chunk.writeUInt32LE(12 + data.length, 8);
  fs.writeSync(output, chunk);
  fs.writeSync(output, data);
  chunks += 1;
  rawBlocks.length = 0;
}

function writeDontCare(blocks) {
  const chunk = Buffer.alloc(12);
  chunk.writeUInt16LE(0xcac3, 0);
  chunk.writeUInt32LE(blocks, 4);
  chunk.writeUInt32LE(12, 8);
  fs.writeSync(output, chunk);
  chunks += 1;
}
