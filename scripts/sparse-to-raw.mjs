import fs from 'node:fs';
import { parseSparseHeader } from './lib/image-format.mjs';

const [, , inputPath, outputPath] = process.argv;
if (!inputPath || !outputPath) {
  throw new Error('usage: sparse-to-raw.mjs input.sparse output.raw');
}

const input = fs.openSync(inputPath, 'r');
const output = fs.openSync(outputPath, 'w');
try {
  const headerBuffer = Buffer.alloc(28);
  fs.readSync(input, headerBuffer, 0, headerBuffer.length, 0);
  const header = parseSparseHeader(headerBuffer);
  const fileHeader = Buffer.alloc(header.fileHeaderSize);
  fs.readSync(input, fileHeader, 0, fileHeader.length, 0);
  let inputOffset = header.fileHeaderSize;
  let outputOffset = 0;

  for (let index = 0; index < header.totalChunks; index += 1) {
    const chunkHeader = Buffer.alloc(header.chunkHeaderSize);
    fs.readSync(input, chunkHeader, 0, chunkHeader.length, inputOffset);
    const type = chunkHeader.readUInt16LE(0);
    const blocks = chunkHeader.readUInt32LE(4);
    const totalSize = chunkHeader.readUInt32LE(8);
    const outputSize = blocks * header.blockSize;
    const dataOffset = inputOffset + header.chunkHeaderSize;

    if (type === 0xcac1) {
      copyRange(input, output, dataOffset, outputOffset, outputSize);
    } else if (type === 0xcac2) {
      const fill = Buffer.alloc(4);
      fs.readSync(input, fill, 0, 4, dataOffset);
      writeFill(output, outputOffset, outputSize, fill);
    } else if (type === 0xcac3) {
      fs.ftruncateSync(output, outputOffset + outputSize);
    } else if (type !== 0xcac4) {
      throw new Error(`unsupported sparse chunk 0x${type.toString(16)}`);
    }
    if (type !== 0xcac4) outputOffset += outputSize;
    inputOffset += totalSize;
  }
  fs.ftruncateSync(output, header.totalBlocks * header.blockSize);
} finally {
  fs.closeSync(input);
  fs.closeSync(output);
}

function copyRange(input, output, inputOffset, outputOffset, length) {
  const buffer = Buffer.alloc(Math.min(8 * 1024 * 1024, Math.max(length, 1)));
  let copied = 0;
  while (copied < length) {
    const size = Math.min(buffer.length, length - copied);
    const read = fs.readSync(input, buffer, 0, size, inputOffset + copied);
    if (read !== size) throw new Error('truncated RAW sparse chunk');
    fs.writeSync(output, buffer, 0, size, outputOffset + copied);
    copied += size;
  }
}

function writeFill(output, outputOffset, length, fill) {
  const buffer = Buffer.alloc(Math.min(8 * 1024 * 1024, Math.max(length, 1)));
  for (let offset = 0; offset < buffer.length; offset += 4) fill.copy(buffer, offset);
  let written = 0;
  while (written < length) {
    const size = Math.min(buffer.length, length - written);
    fs.writeSync(output, buffer, 0, size, outputOffset + written);
    written += size;
  }
}
