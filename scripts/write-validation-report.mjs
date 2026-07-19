import fs from 'node:fs';

const outputPath = process.argv[2];
if (!outputPath) throw new Error('validation report path is required');

const report = {
  schema_version: 1,
  result: 'passed',
  scope: 'hosted-runner-image-validation',
  hardware_boot_tested: false,
  one_kvm_version: process.env.ONE_KVM_VERSION,
  one_kvm_release: process.env.UPSTREAM_TAG,
  package_sha256: process.env.PACKAGE_DIGEST,
  build_tag: process.env.BUILD_TAG,
  build_number: Number(process.env.BUILD_NUMBER),
  builder_commit: process.env.BUILDER_COMMIT,
  checks: [
    'Amlogic container unpack and CRC',
    'Amlogic commands and unchanged non-rootfs partitions',
    'partition VERIFY SHA-1 values',
    'sparse round-trip and ext4 consistency',
    'One-KVM armhf package and ARM ELF binary',
    'systemd service and WS1608 OTG configuration',
    'image release metadata and build-only file removal',
  ],
};

fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
