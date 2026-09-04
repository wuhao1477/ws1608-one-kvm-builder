import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const sources = fs.readFileSync('experimental/hcodec/config/sources.env', 'utf8');
const builder = fs.readFileSync('experimental/hcodec/scripts/build-tools.sh', 'utf8');
const firmwareBuilder = 'experimental/hcodec/scripts/build-firmware.sh';
const workflow = fs.readFileSync('.github/workflows/hcodec-candidate.yml', 'utf8');

test('locks the Hardkernel Meson8b dblk microcode input and deterministic output', () => {
  for (const value of [
    'FIRMWARE_INPUT_PATH=drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h',
    'FIRMWARE_WORD_COUNT=2384',
    'FIRMWARE_OUTPUT_SIZE=9536',
    'FIRMWARE_OUTPUT_SHA256=2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368',
  ]) {
    assert.match(sources, new RegExp(value.replace(/[.*+?^${}()|[\\]\\]/g, '\\\\$&')));
  }
});

test('does not select the old GXL container record for Meson8b firmware', () => {
  assert.doesNotMatch(builder, /gxl_h264_enc|h264_enc\.bin/);
});

test('builds the pinned Meson8b firmware from the exact Hardkernel header', () => {
  assert.equal(fs.existsSync(firmwareBuilder), true, `${firmwareBuilder} must exist`);
  const source = fs.readFileSync(firmwareBuilder, 'utf8');
  for (const value of [
    'FIRMWARE_ARCHIVE_URL', 'FIRMWARE_ARCHIVE_SHA256', 'FIRMWARE_INPUT_PATH',
    'extract-meson8b-ucode.py', 'FIRMWARE_WORD_COUNT', 'FIRMWARE_OUTPUT_SIZE',
    'FIRMWARE_OUTPUT_SHA256', 'firmware-manifest.json',
  ]) {
    assert.match(source, new RegExp(value.replace(/[.*+?^${}()|[\\]\\]/g, '\\\\$&')));
  }
  assert.match(source, /wc -c/);
  assert.doesNotMatch(source, /stat -c/);
});

test('workflow generates firmware before packaging it into the artifact', () => {
  assert.match(workflow, /build-firmware\.sh/);
  assert.match(workflow, /out\/hcodec\/firmware/);
  assert.match(workflow, /package-artifact\.sh[^\n]+out\/hcodec\/firmware/);
});
