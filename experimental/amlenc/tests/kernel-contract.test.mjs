import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const files = {
  board: 'experimental/amlenc/patches/kernel/0001-ws1608-vendor-dts.patch',
  encoder: 'experimental/amlenc/patches/kernel/0002-enable-amvenc-avc.patch',
  build: 'experimental/amlenc/scripts/build-kernel.sh',
  verify: 'experimental/amlenc/scripts/verify-build.sh',
  verifyConfig: 'experimental/amlenc/scripts/verify-kernel-config.sh',
};

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

test('adapts the vendor board without ODROID-only GPIO consumers', () => {
  const patch = readRequired(files.board);

  assert.match(patch, /model = "WS1608 OneCloud"/);
  assert.match(patch, /reset_pin = "GPIOH_4"/);
  assert.match(patch, /gpio-hub-rst = "GPIOAO_4"/);
  assert.match(patch, /gpio-vbus-power = "GPIOAO_5"/);
  assert.match(patch, /^-.*(?:Hardkernel|ODROID|GPIOX_1|GPIOX_2|odroid_pwm0|odroid_pwm1)/m);
  assert.match(patch, /^-\s*odroid_pwm0:odroid_pwm0/m);
  assert.match(patch, /^-\s*odroid_pwm1:odroid_pwm1/m);
  assert.doesNotMatch(patch, /^\+.*(?:Hardkernel|ODROID|GPIOX_1|GPIOX_2|odroid_pwm0|odroid_pwm1)/m);
});

test('binds the H.264 encoder to exactly 18 MiB of contiguous memory', () => {
  const patch = readRequired(files.encoder);

  assert.match(patch, /region_name = "cma_encoder"/);
  assert.match(patch, /reg = <0x0 0x01200000>/);
  assert.match(patch, /compatible = "amlogic,amvenc_avc"/);
  assert.match(patch, /linux,contiguous-region = <&cma_encoder>/);
  assert.match(patch, /status = "okay"/);
});

test('builds and independently verifies traceable kernel artifacts', () => {
  const build = readRequired(files.build);
  const verify = readRequired(files.verify);
  const verifyConfig = readRequired(files.verifyConfig);

  for (const required of ['zImage', 'ws1608-s805.dtb', 'modules.tar.gz', 'kernel.config', 'source-manifest.json', 'SHA256SUMS']) {
    assert.match(build, new RegExp(required.replaceAll('.', '\\.')));
  }
  assert.match(build, /arm-linux-gnueabihf-/);
  assert.match(build, /--enable CMA/);
  assert.match(build, /--enable AMLOGIC_ION/);
  assert.match(build, /--enable USB_GADGET/);
  assert.match(build, /--enable AM_ENCODER/);
  assert.match(build, /--disable MALI400/);
  assert.match(build, /--disable MALI450/);
  assert.match(build, /--disable FB_AMLOGIC_UMP/);
  assert.match(build, /--disable FB_TFT/);
  assert.match(build, /--disable UMP/);
  assert.doesNotMatch(build, /--disable (?:IP_NF_TARGET_ECN|NETFILTER_XT_TARGET_DSCP)/);
  assert.match(build, /case-sensitive-probe/);
  assert.match(build, /requires a case-sensitive work directory/);
  assert.match(build, /git -C "\$SOURCE_DIR" add --all/);
  assert.match(build, /verify-kernel-source-diff\.sh/);
  assert.match(build, /HOSTCFLAGS=.*-fcommon/);
  assert.match(build, /KCFLAGS=.*-march=armv7-a/);
  assert.match(build, /-dumpfullversion/);
  assert.match(build, /compiler_major.*-le 7/);
  assert.match(build, /"toolchain":\{.*"gcc":"\$compiler_version"/);
  assert.match(build, /kernel-patch-digest\.sh/);

  assert.match(verify, /sha256sum --check/);
  assert.match(verify, /readelf.*-h/);
  assert.match(verify, /dtc -I dtb -O dts/);
  assert.match(verify, /grep -a[q ]+.*vmlinux/);
  assert.doesNotMatch(verify, /strings .*vmlinux.*\|.*grep -q/);
  assert.match(verify, /3\.10\.107/);
  assert.match(verify, /verify-kernel-config\.sh/);
  assert.match(verify, /\.toolchain\.gcc/);
  assert.match(verify, /amlogic,amvenc_avc/);
  assert.match(verify, /0x01200000|0x1200000/);
  assert.match(verify, /pinname = "emmc"/);
  assert.match(verify, /amlogic,meson-eth/);
  assert.match(verify, /amlogic,amhdmitx/);
  assert.match(verify, /verify-kernel-source-diff\.sh/);
  assert.match(verify, /patches_sha256/);
  assert.match(verifyConfig, /FB_AMLOGIC_UMP/);
  assert.match(verifyConfig, /FB_TFT/);
  assert.match(verifyConfig, /--state/);
});
