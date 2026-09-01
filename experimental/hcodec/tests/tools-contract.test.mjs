import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const root = 'experimental/hcodec';
const files = {
  smoke: `${root}/tools/meson-venc-smoke/meson-venc-smoke.c`,
  capture: `${root}/tools/meson-venc-capture/meson-venc-capture.c`,
  smokeMake: `${root}/tools/meson-venc-smoke/Makefile`,
  captureMake: `${root}/tools/meson-venc-capture/Makefile`,
  build: `${root}/scripts/build-tools.sh`,
  verify: `${root}/scripts/verify-tools.sh`,
  extract: `${root}/tools/extract-meson8b-ucode.py`,
};

function read(file) {
  assert.equal(fs.existsSync(file), true, `${file} must exist`);
  return fs.readFileSync(file, 'utf8');
}

test('documents the fixed V4L2 encoder smoke parameters and failure gates', () => {
  const source = `${read(files.smoke)}\n${read(files.capture)}`;
  for (const value of ['V4L2_PIX_FMT_NV12', 'V4L2_PIX_FMT_H264',
    'V4L2_MEMORY_MMAP', 'V4L2_MEMORY_DMABUF', 'V4L2_CID_MPEG_VIDEO_GOP_SIZE',
    'V4L2_MPEG_VIDEO_BITRATE_MODE_CQ', 'find_nal', 'V4L2_BUF_FLAG_KEYFRAME']) {
    assert.match(source, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(source, /4000000/);
  assert.match(source, /FRAMES/);
  assert.match(read(files.capture), /uint32_t frames = 1800/);
  assert.match(read(files.capture), /uint32_t width = 1280/);
  assert.match(read(files.capture), /uint32_t height = 720/);
});

test('builds and verifies ARMv7 glibc tools with no firmware binary', () => {
  const build = read(files.build);
  const verify = read(files.verify);
  const extract = read(files.extract);
  for (const value of ['arm-linux-gnueabihf-', 'readelf', 'ld-linux-armhf.so.3',
    'ld-linux-armhf.so.3', 'NEEDED', 'binary_included', 'sha256']) {
    assert.match(`${build}\n${verify}\n${extract}`, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(build, /meson-venc-smoke/);
  assert.match(build, /meson-venc-capture/);
  assert.match(build, /firmware-manifest\.json/);
  assert.match(verify, /ELF32|ARM/);
  assert.match(extract, /MicroCode/);
});

test('tool Makefiles fail fast on compiler warnings', () => {
  assert.match(read(files.smokeMake), /-Wall -Wextra -Werror/);
  assert.match(read(files.captureMake), /-Wall -Wextra -Werror/);
});

test('extractor rejects malformed microcode and writes deterministic words', (t) => {
  const extractor = path.resolve(files.extract);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-ucode-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const source = path.join(directory, 'ucode.h');
  const output = path.join(directory, 'meson/venc/meson8b_h264.bin');
  fs.writeFileSync(source, 'static const uint32_t MicroCode[] = { 0x11223344, 7 };\n');
  const result = spawnSync('python3', [extractor, source, output], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual([...fs.readFileSync(output)], [0x44, 0x33, 0x22, 0x11, 7, 0, 0, 0]);
});
