import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const verifier = path.resolve('experimental/hcodec/scripts/verify-config-diff.sh');
const baseline = `CONFIG_MODULES=y
CONFIG_FW_LOADER=y
CONFIG_MEDIA_SUPPORT=m
CONFIG_VIDEO_DEV=m
CONFIG_V4L2_MEM2MEM_DEV=m
CONFIG_VIDEOBUF2_DMA_CONTIG=m
CONFIG_MESON_CANVAS=y
`;

function verify(candidate) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-config-diff-'));
  const stable = path.join(directory, 'stable.config');
  const built = path.join(directory, 'built.config');
  fs.writeFileSync(stable, baseline);
  fs.writeFileSync(built, candidate);
  const result = spawnSync('bash', [verifier, stable, built], { encoding: 'utf8' });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

test('accepts only the Meson VENC module addition', () => {
  const result = verify(`${baseline}CONFIG_VIDEO_MESON_VENC=m\n`);

  assert.equal(result.status, 0, result.stderr);
});

test('rejects a change to an existing stable dependency', () => {
  const candidate = `${baseline}CONFIG_VIDEO_MESON_VENC=m\n`
    .replace('CONFIG_V4L2_MEM2MEM_DEV=m', 'CONFIG_V4L2_MEM2MEM_DEV=y');

  assert.notEqual(verify(candidate).status, 0);
});

test('rejects a missing required Meson VENC module', () => {
  assert.notEqual(verify(baseline).status, 0);
});
