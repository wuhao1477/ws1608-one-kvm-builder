import fs from 'node:fs';

const SPARSE_MAGIC = 0xed26ff3a;
const AMLOGIC_MAGIC = 0x27b51956;
const AMLOGIC_HEADER_SIZE = 64;
const ITEM_SIZE = { 1: 128, 2: 576 };

function cString(buffer, offset, length) {
  const end = buffer.indexOf(0, offset);
  const limit = end === -1 ? offset + length : end;
  return buffer.subarray(offset, Math.min(limit, offset + length)).toString('ascii');
}

function makeCrcTable() {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}

const CRC_TABLE = makeCrcTable();

export function amlCrc32(buffer, initial = 0xffffffff) {
  let crc = initial >>> 0;
  for (const byte of buffer) {
    crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return crc >>> 0;
}

export function parseSparseHeader(buffer) {
  if (buffer.length < 28 || buffer.readUInt32LE(0) !== SPARSE_MAGIC) {
    throw new Error('invalid sparse magic');
  }
  const majorVersion = buffer.readUInt16LE(4);
  if (majorVersion !== 1) throw new Error(`unsupported sparse version ${majorVersion}`);
  const fileHeaderSize = buffer.readUInt16LE(8);
  const chunkHeaderSize = buffer.readUInt16LE(10);
  const blockSize = buffer.readUInt32LE(12);
  const totalBlocks = buffer.readUInt32LE(16);
  const totalChunks = buffer.readUInt32LE(20);
  if (fileHeaderSize < 28 || chunkHeaderSize < 12 || blockSize === 0) {
    throw new Error('invalid sparse header sizes');
  }
  return {
    majorVersion,
    fileHeaderSize,
    chunkHeaderSize,
    blockSize,
    totalBlocks,
    totalChunks,
  };
}

export function parseAmlogicImage(buffer) {
  if (buffer.length < AMLOGIC_HEADER_SIZE) throw new Error('Amlogic image is truncated');
  const version = buffer.readUInt32LE(4);
  const magic = buffer.readUInt32LE(8);
  if (magic !== AMLOGIC_MAGIC) throw new Error('invalid Amlogic image magic');
  const itemSize = ITEM_SIZE[version];
  if (!itemSize) throw new Error(`unsupported Amlogic image version ${version}`);
  const itemCount = buffer.readUInt32LE(24);
  const tableEnd = AMLOGIC_HEADER_SIZE + itemSize * itemCount;
  if (tableEnd > buffer.length) throw new Error('Amlogic item table is truncated');

  const items = [];
  for (let index = 0; index < itemCount; index += 1) {
    const offset = AMLOGIC_HEADER_SIZE + index * itemSize;
    const imgType = buffer.readUInt32LE(offset + 4);
    const imageOffset = Number(buffer.readBigUInt64LE(offset + 16));
    const size = Number(buffer.readBigUInt64LE(offset + 24));
    const textOffset = offset + 32;
    const textLength = version === 1 ? 32 : 256;
    items.push({
      id: buffer.readUInt32LE(offset),
      imgType,
      imageOffset,
      size,
      type: cString(buffer, textOffset, textLength),
      name: cString(buffer, textOffset + textLength, textLength),
    });
  }

  const storedCrc = buffer.readUInt32LE(0);
  const calculatedCrc = amlCrc32(buffer.subarray(4));
  return {
    version,
    size: Number(buffer.readBigUInt64LE(12)),
    alignSize: buffer.readUInt32LE(20),
    itemCount,
    items,
    storedCrc,
    calculatedCrc,
    crcValid: storedCrc === calculatedCrc,
  };
}

export function readAmlogicImage(filePath) {
  return parseAmlogicImage(fs.readFileSync(filePath));
}

export { AMLOGIC_MAGIC, SPARSE_MAGIC };
