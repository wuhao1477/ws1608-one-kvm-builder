import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const files = {
  build: 'experimental/hcodec/scripts/build-kernel.sh',
  verify: 'experimental/hcodec/scripts/verify-kernel.sh',
  verifySigning: 'experimental/hcodec/scripts/verify-module-signing.sh',
};

function readRequired(file) {
  assert.equal(fs.existsSync(file), true, `${file} must exist`);
  return fs.readFileSync(file, 'utf8');
}

test('builds the fixed ARMv7 kernel artifact set without automatic module loading', () => {
  const build = readRequired(files.build);

  for (const value of ['ARCH=arm', 'arm-linux-gnueabihf-', 'LOCALVERSION=-current-meson',
    'CONFIG_VIDEO_MESON_VENC', 'zImage', 'uImage', 'meson8b-onecloud.dtb',
    'modules.tar.xz', 'kernel.config', 'System.map', 'Module.symvers',
    'source-manifest.json', 'module-signing.json', 'SHA256SUMS']) {
    assert.match(build, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(build, /kernel-patches-to-git/);
  assert.match(build, /zz-hcodec-/);
  assert.match(build, /ARMBIAN_DRIVERS_HASH/);
  assert.match(build, /verify-config-diff\.sh/);
  assert.match(build, /\[\[ -e "\$SOURCE_DIR\/\.git" && ! -L "\$SOURCE_DIR\/\.git" \]\]/);
  assert.match(build, /Armbian kernel worktree status:/);
  assert.match(build, /git -C "\$SOURCE_DIR" clean -f -- '\*\.orig'/);
  assert.match(build, /git -C "\$SOURCE_DIR" status --porcelain=v1 --untracked-files=all >&2/);
  assert.match(build, /expected_status=' M drivers\/media\/platform\/amlogic\/meson-venc\/meson-venc\.c'/);
  assert.match(build, /power_off: begin/);
  assert.match(build, /unexpected changes/);
  assert.doesNotMatch(build, /find "\$SOURCE_DIR" -type f -name '\*\.orig' -delete/);
  assert.doesNotMatch(build, /modules-load|modprobe|ONE_KVM/);
});

test('verifies architecture, release, boot addresses, DT and module signing', () => {
  const verify = readRequired(files.verify);
  const signing = readRequired(files.verifySigning);

  for (const value of ['readelf', 'modinfo', '6.12.28-current-meson', 'dtc -I dtb -O dts',
    'amlogic,meson8b-hcodec', 'status = "okay"', 'mkimage -l', '0x00208000',
    'sha256sum --check', 'verify-config-diff.sh', 'verify-module-signing.sh',
    'automatic_module_loading', 'ARMBIAN_PATCHES_HASH']) {
    assert.match(`${verify}\n${signing}`, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(signing, /CONFIG_MODULE_SIG/);
});
