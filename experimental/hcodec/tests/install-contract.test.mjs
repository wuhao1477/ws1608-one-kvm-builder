import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const installer = 'experimental/hcodec/scripts/install-artifact.sh';

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result;
}

test('installs modules without replacing a target /lib symlink', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hcodec-install-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const artifact = path.join(root, 'artifact');
  const target = path.join(root, 'target');
  const moduleStage = path.join(root, 'module-stage', 'lib', 'modules', '6.12.28-current-meson');
  fs.mkdirSync(path.join(artifact, 'kernel'), { recursive: true });
  fs.mkdirSync(path.join(artifact, 'firmware'), { recursive: true });
  fs.mkdirSync(moduleStage, { recursive: true });
  fs.mkdirSync(path.join(target, 'usr', 'lib'), { recursive: true });
  fs.mkdirSync(path.join(target, 'boot', 'dtb'), { recursive: true });
  fs.mkdirSync(path.join(target, 'root'), { recursive: true });
  fs.symlinkSync('usr/lib', path.join(target, 'lib'));
  fs.writeFileSync(path.join(moduleStage, 'meson-venc.ko'), 'module');
  fs.writeFileSync(path.join(moduleStage, 'modules.order'), 'kernel/drivers/media/platform/amlogic/meson-venc/meson-venc.ko\n');
  fs.writeFileSync(
    path.join(moduleStage, 'modules.dep'),
    'kernel/drivers/block/zram/zram.ko: kernel/mm/zsmalloc.ko kernel/lib/842/842_decompress.ko kernel/lib/842/842_compress.ko\n',
  );
  for (const file of ['modules.dep.bin', 'modules.alias', 'modules.alias.bin']) {
    fs.writeFileSync(path.join(moduleStage, file), 'index');
  }
  run('tar', ['-cJf', path.join(artifact, 'kernel', 'modules.tar.xz'), '-C', path.join(root, 'module-stage'), '.']);
  fs.writeFileSync(path.join(artifact, 'kernel', 'uImage'), 'uImage');
  fs.writeFileSync(path.join(artifact, 'kernel', 'System.map'), 'System.map');
  fs.writeFileSync(path.join(artifact, 'kernel', 'kernel.config'), 'config');
  fs.writeFileSync(path.join(artifact, 'kernel', 'meson8b-onecloud.dtb'), 'dtb');
  fs.writeFileSync(path.join(artifact, 'manifest.json'), JSON.stringify({ kernel_release: '6.12.28-current-meson' }));
  fs.writeFileSync(path.join(artifact, 'firmware', 'meson8b_h264.bin'), 'firmware');
  fs.writeFileSync(path.join(target, 'lib', 'firmware-placeholder'), 'placeholder');

  const result = spawnSync('bash', [installer, artifact, target], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.lstatSync(path.join(target, 'lib')).isSymbolicLink(), true);
  assert.equal(fs.readFileSync(path.join(target, 'lib', 'modules', '6.12.28-current-meson', 'meson-venc.ko'), 'utf8'), 'module');
  assert.equal(fs.readFileSync(path.join(target, 'lib', 'firmware', 'meson', 'venc', 'meson8b_h264.bin'), 'utf8'), 'firmware');
});

test('installer source uses a staging tree and never extracts modules at filesystem root', () => {
  const source = fs.readFileSync(installer, 'utf8');
  assert.match(source, /mktemp/);
  assert.match(source, /modules-stage/);
  assert.match(source, /TARGET_ROOT.*hcodec-modules-stage/);
  assert.match(source, /modules\/\$KERNEL_RELEASE/);
  assert.doesNotMatch(source, /tar -xJf [^\n]+ -C \/(?:\s|$)/);
  assert.match(source, /4000000/);
  assert.match(source, /cma=128M/);
  assert.match(source, /meson8b_h264\.bin/);
  assert.match(source, /backups\/install-/);
  assert.match(source, /FIRMWARE_DIR.*meson8b_h264\.bin/);
  assert.doesNotMatch(source, /\/video\/h264_enc\.bin|gxl_h264_enc|zlib/);
});

test('preserves the build-time module dependency indexes on live-root installs', () => {
  const source = fs.readFileSync(installer, 'utf8');

  assert.doesNotMatch(source, /\bdepmod\b/);
  assert.match(source, /for index in modules\.order modules\.dep modules\.dep\.bin/);
  assert.match(source, /zram\\\.ko: .*kernel\/mm\/zsmalloc\\\.ko/);
});
