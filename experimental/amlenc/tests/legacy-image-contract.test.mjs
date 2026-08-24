import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const files = {
  config: 'experimental/amlenc/config/legacy-bringup.env',
  rootfs: 'experimental/amlenc/scripts/build-legacy-rootfs.sh',
  image: 'experimental/amlenc/scripts/build-legacy-bringup-image.sh',
  verify: 'experimental/amlenc/scripts/verify-legacy-bringup-image.sh',
};

function readRequired(filePath) {
  assert.equal(fs.existsSync(filePath), true, `${filePath} must exist`);
  return fs.readFileSync(filePath, 'utf8');
}

test('defines fixed legacy bring-up partition and kernel identities', () => {
  const config = readRequired(files.config);
  assert.match(config, /^LEGACY_ROOTFS_UUID=7c59bb76-d17e-4a9c-9ff8-031b35133010$/m);
  assert.match(config, /^LEGACY_ROOTFS_BYTES=1400897536$/m);
  assert.match(config, /^LEGACY_BOOT_BYTES=268435456$/m);
  assert.match(config, /^RECOVERY_KERNEL=6\.12\.28-current-meson$/m);
  assert.match(config, /^LEGACY_KERNEL=3\.10\.107$/m);
  assert.match(config, /^RECOVERY_BOOT_LABEL=armbi_boot$/m);
});

test('independently verifies recovery identity, rootfs and untested status', () => {
  const verify = readRequired(files.verify);
  assert.match(verify, /AmlImg|AMLIMG_BIN/);
  assert.match(verify, /cmp[\s\S]*base[\s\S]*final/);
  assert.match(verify, /name.*!=.*boot.*name.*!=.*rootfs/);
  assert.match(verify, /sha1sum/);
  assert.match(verify, /e2fsck/);
  assert.match(verify, /mcopy/);
  assert.match(verify, /mkimage -l/);
  assert.match(verify, /debugfs/);
  assert.match(verify, /uImage\.recovery/);
  assert.match(verify, /uInitrd\.recovery/);
  assert.match(verify, /6\.12\.28-current-meson/);
  assert.match(verify, /3\.10\.107/);
  assert.match(verify, /ws1608-amlenc-arm-trial/);
  assert.match(verify, /ws1608-amlenc-mark-success/);
  assert.match(verify, /PasswordAuthentication no/);
  assert.match(verify, /one-kvm/);
  for (const field of ['hardware_boot_tested', 'hardware_encoder_tested', 'one_kvm_included', 'hid_tested', 'msd_tested']) {
    assert.match(verify, new RegExp(`${field}.*false`));
  }
});

test('builds a Bullseye SysV rootfs for both kernels without One-KVM', () => {
  const rootfs = readRequired(files.rootfs);
  assert.match(rootfs, /BULLSEYE_ARMV7_OCI_IMAGE/);
  for (const packageName of ['sysvinit-core', 'udev', 'kmod', 'ifupdown', 'isc-dhcp-client', 'openssh-server']) {
    assert.match(rootfs, new RegExp(packageName));
  }
  assert.match(rootfs, /passwd -l root/);
  assert.match(rootfs, /PasswordAuthentication no/);
  assert.match(rootfs, /PubkeyAuthentication yes/);
  assert.match(rootfs, /ssh-keygen -A/);
  assert.match(rootfs, /authorized_keys/);
  assert.match(rootfs, /RECOVERY_ROOTFS_RAW/);
  assert.match(rootfs, /LEGACY_MODULES_TAR/);
  assert.match(rootfs, /lib\/modules\/6\.12\.28-current-meson/);
  assert.match(rootfs, /ws1608-amlenc-arm-trial/);
  assert.match(rootfs, /ws1608-amlenc-mark-success/);
  assert.match(rootfs, /LABEL=armbi_boot \/boot vfat/);
  assert.match(rootfs, /proc \/proc proc/);
  assert.match(rootfs, /tmpfs \/run tmpfs/);
  assert.doesNotMatch(rootfs, /one-kvm\.deb|\/usr\/bin\/one-kvm/);
});

test('assembles dual boot and rootfs partitions inside the stable AmlImg package', () => {
  const image = readRequired(files.image);
  assert.match(image, /BASE_IMAGE_XZ/);
  assert.match(image, /AMLIMG_BIN/);
  assert.match(image, /sparse-to-raw\.mjs/);
  assert.match(image, /raw-to-sparse\.mjs/);
  assert.match(image, /build-legacy-rootfs\.sh/);
  assert.match(image, /render-legacy-trial-boot\.mjs/);
  for (const asset of [
    'uImage.recovery', 'uInitrd.recovery', 'meson8b-onecloud.recovery.dtb',
    'uImage.amlenc', 'meson8b-onecloud-amlenc.dtb', 'amlenc-force-recovery',
  ]) assert.match(image, new RegExp(asset.replaceAll('.', '\\.')));
  assert.match(image, /mkimage.*Linux-3\.10\.107-WS1608-AMLENC/s);
  assert.match(image, /sha1sum/);
  assert.match(image, /stable_channel_modified:\s*false/);
  assert.match(image, /hardware_boot_tested:\s*false/);
  assert.match(image, /hardware_encoder_tested:\s*false/);
  assert.match(image, /one_kvm_included:\s*false/);
  assert.doesNotMatch(image, /DIAGNOSTIC_IMAGE|DIAGNOSTIC_MANIFEST/);
});
