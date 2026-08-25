import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const builderPath = 'experimental/amlenc/scripts/build-burn-image.sh';
const verifierPath = 'experimental/amlenc/scripts/verify-burn-image.sh';
const packagerPath = 'experimental/amlenc/scripts/package-burn-release.sh';
const releaseVerifierPath = 'experimental/amlenc/scripts/verify-burn-release.sh';
const loginConfiguratorPath = 'experimental/amlenc/scripts/configure-login-postinst.sh';
const loginConfigPath = 'experimental/amlenc/config/login.env';
const workflowPath = '.github/workflows/amlenc-experimental.yml';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

test('defines an isolated burn image build and verification chain', () => {
  assert.equal(fs.existsSync(builderPath), true, 'burn image builder is required');
  assert.equal(fs.existsSync(verifierPath), true, 'burn image verifier is required');
  assert.equal(fs.existsSync(packagerPath), true, 'burn release packager is required');
  assert.equal(fs.existsSync(loginConfiguratorPath), true, 'burn login configurator is required');
  assert.equal(fs.existsSync(loginConfigPath), true, 'burn login config is required');
  const builder = read(builderPath);
  const oneKvmBuilder = read('experimental/amlenc/scripts/build-one-kvm.sh');
  const verifier = read(verifierPath);
  const packager = read(packagerPath);
  const loginConfigurator = read(loginConfiguratorPath);
  assert.match(builder, /AmlImg/);
  assert.match(builder, /build-image\.sh/);
  assert.match(builder, /one_kvm/);
  assert.match(builder, /hardware_encoder_tested/);
  assert.match(verifier, /AmlImg.*unpack|unpack.*AmlImg/s);
  assert.match(verifier, /sha1sum/);
  assert.match(verifier, /e2fsck/);
  assert.match(verifier, /one[-_]kvm/);
  assert.match(verifier, /hardware_encoder_tested/);
  assert.match(packager, /xz/);
  assert.match(packager, /SHA256SUMS/);
  assert.match(oneKvmBuilder, /configure-login-postinst\.sh/);
  const loginConfig = read(loginConfigPath);
  assert.match(loginConfigurator, /config\/login\.env/);
  assert.match(loginConfig, /^DEFAULT_LOGIN_USER=root$/m);
  assert.match(loginConfig, /^DEFAULT_LOGIN_PASSWORD=ws1608$/m);
  assert.match(loginConfigurator, /chpasswd/);
  assert.match(loginConfigurator, /passwd -u/);
  assert.match(loginConfigurator, /last_exit/);
  assert.match(loginConfigurator, /PasswordAuthentication yes/);
  assert.match(loginConfigurator, /PermitRootLogin yes/);
});

test('builds the flashable experiment from the verified stable boot chain', () => {
  const builder = read(builderPath);
  const verifier = read(verifierPath);
  const workflow = read(workflowPath);

  assert.match(builder, /ONE_KVM_DEB/);
  assert.match(builder, /package_prefix=.*ONE_KVM_VERSION.*ws1608amlenc/);
  assert.match(builder, /package_build=.*package_version#/);
  assert.doesNotMatch(builder, /DIAGNOSTIC_IMAGE|DIAGNOSTIC_MANIFEST|BOOT_RAW/);
  assert.doesNotMatch(builder, /3\.10\.107/);
  assert.match(builder, /stable_base_preserved/);
  assert.match(builder, /BASE_IMAGE_SHA256/);
  assert.match(builder, /BASE_KERNEL/);

  assert.match(verifier, /cmp[^\n]*base[^\n]*final|cmp[^\n]*final[^\n]*base/);
  assert.match(verifier, /name[^\n]*!=[^\n]*rootfs/);
  assert.match(verifier, /stable_base_preserved/);
  assert.match(verifier, /BASE_KERNEL/);
  assert.match(verifier, /3\.10\.107/);
  assert.match(verifier, /PasswordAuthentication yes/);
  assert.match(verifier, /PermitRootLogin yes/);
  assert.match(verifier, /cat \/etc\/shadow/);

  assert.match(workflow, /ONE_KVM_DEB:/);
  assert.match(workflow, /IMAGE_NAME="\$AMLENC_IMAGE_NAME"[\s\S]{0,200}build-burn-image\.sh/);
  assert.doesNotMatch(workflow, /DIAGNOSTIC_IMAGE:|DIAGNOSTIC_MANIFEST:/);
  assert.doesNotMatch(workflow, /bullseye_3\.10\.107\.burn\.img/);
});

test('inserts login setup before an existing Debian postinst exit', (t) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-login-postinst-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const packageDir = path.join(fixture, 'package');
  fs.mkdirSync(path.join(packageDir, 'DEBIAN'), { recursive: true });
  fs.writeFileSync(path.join(packageDir, 'DEBIAN', 'postinst'), '#!/bin/sh\nset -e\necho original\nexit 0\n', { mode: 0o755 });

  const result = spawnSync('bash', ['experimental/amlenc/scripts/configure-login-postinst.sh', packageDir], {
    cwd: process.cwd(), encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const postinst = fs.readFileSync(path.join(packageDir, 'DEBIAN', 'postinst'), 'utf8');
  assert.match(postinst, /chpasswd/);
  assert.ok(postinst.indexOf('chpasswd') < postinst.indexOf('exit 0'));
  assert.match(postinst, /PasswordAuthentication yes/);
  assert.equal(spawnSync('sh', ['-n', path.join(packageDir, 'DEBIAN', 'postinst')]).status, 0);
});

test('runs burn image gates before metadata upload and keeps hardware gate explicit', () => {
  const workflow = read(workflowPath);
  assert.match(workflow, /Build experimental burn image/);
  assert.match(workflow, /Verify experimental burn image/);
  assert.match(workflow, /Package experimental burn metadata/);
  assert.match(workflow, /hardware_encoder_tested.*false|hardware_encoder_tested.*true/s);
  const buildIndex = workflow.indexOf('Build experimental burn image');
  const diagnosticIndex = workflow.indexOf('Build diagnostic USB image with One-KVM');
  const verifyIndex = workflow.indexOf('Verify experimental burn image');
  const uploadIndex = workflow.indexOf('Upload experimental release artifact');
  assert.ok(buildIndex >= 0 && diagnosticIndex > buildIndex && verifyIndex > buildIndex && uploadIndex > verifyIndex);
});

test('records the verified four-codec software baseline in the burn candidate', () => {
  const builder = read(builderPath);
  const verifier = read(verifierPath);
  const packager = read(packagerPath);
  const releaseVerifier = read(releaseVerifierPath);
  const workflow = read(workflowPath);

  for (const source of [builder, verifier, packager, releaseVerifier]) assert.match(source, /codec_baseline/);
  assert.match(builder, /SOFTWARE_CODECS_RUNTIME_VERIFIED/);
  assert.match(builder, /software_codecs/);
  assert.match(verifier, /ws1608-amlenc-build\.json/);
  assert.match(verifier, /runtime_verified:true/);
  assert.match(workflow, /SOFTWARE_CODECS_RUNTIME_VERIFIED=true/);
  assert.match(workflow, /GITHUB_ENV/);
});

test('keeps untested hardware status explicit in the experimental prerelease', () => {
  const workflow = read(workflowPath);
  assert.match(workflow, /RELEASE_PRERELEASE: 'true'/);
  assert.match(workflow, /hardware_encoder_tested.*false/s);
  assert.match(workflow, /hardware_boot_tested.*false/s);
});

test('verifies exactly five packaged burn release assets', (t) => {
  assert.equal(fs.existsSync(releaseVerifierPath), true, 'burn release verifier is required');
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-burn-release-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const imageName = 'WS1608-AMLENC_0.2.6+ws1608amlenc.run-1-1_Onecloud_trixie_6.12.28.burn.img';
  const image = path.join(fixture, imageName);
  fs.writeFileSync(image, 'burn-image-fixture');
  assert.equal(spawnSync('xz', ['-k', image], { encoding: 'utf8' }).status, 0);
  const digest = (file) => spawnSync('sha256sum', [file], { encoding: 'utf8' }).stdout.split(/\s+/)[0];
  const manifest = {
    schema: 1,
    kind: 'ws1608-amlenc-burn-image',
    image_name: imageName,
    image_sha256: digest(image),
    build_tag: 'ws1608-amlenc-exp-0.2.6-v260802-k6.12.28-b001001',
    stable_base_preserved: true,
    base_release_tag: 'base-20260804-consolefix',
    base_image_name: 'Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-consolefix.burn.img.xz',
    base_image_sha256: 'b'.repeat(64),
    kernel: { version: '6.12.28-current-meson', source: 'stable-base' },
    one_kvm: { version: '0.2.6+ws1608amlenc.run-1-1', sha256: 'a'.repeat(64) },
    codec_baseline: { software: ['h264', 'h265', 'vp8', 'vp9'], hardware: [], runtime_verified: true },
    default_login_user: 'root',
    password_authentication: true,
    ssh_service_enabled: true,
    hardware_boot_tested: false,
    hardware_encoder_tested: false,
    one_kvm_included: true,
    stable_channel_modified: false,
  };
  fs.writeFileSync(path.join(fixture, 'manifest.json'), `${JSON.stringify(manifest)}\n`);
  const report = {
    schema: 1,
    result: 'pending',
    hardware_boot_tested: false,
    hardware_encoder_tested: false,
    assets: {
      image: { name: imageName, sha256: digest(image) },
      compressed_image: { name: `${imageName}.xz`, sha256: digest(`${image}.xz`) },
      manifest: { name: 'manifest.json', sha256: digest(path.join(fixture, 'manifest.json')) },
    },
  };
  fs.writeFileSync(path.join(fixture, 'validation-report.json'), `${JSON.stringify(report)}\n`);
  const checksumFiles = [imageName, `${imageName}.xz`, 'manifest.json', 'validation-report.json'];
  fs.writeFileSync(
    path.join(fixture, 'SHA256SUMS'),
    checksumFiles.map((name) => `${digest(path.join(fixture, name))}  ${name}`).join('\n') + '\n',
  );

  const result = spawnSync('bash', [releaseVerifierPath, fixture], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /verified experimental burn release assets/);

  fs.writeFileSync(path.join(fixture, 'unexpected.txt'), 'unexpected');
  const rejected = spawnSync('bash', [releaseVerifierPath, fixture], { encoding: 'utf8' });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /exactly five/i);

  fs.rmSync(path.join(fixture, 'unexpected.txt'));
  fs.writeFileSync(path.join(fixture, '.hidden'), 'unexpected');
  const hiddenRejected = spawnSync('bash', [releaseVerifierPath, fixture], { encoding: 'utf8' });
  assert.notEqual(hiddenRejected.status, 0);
  assert.match(hiddenRejected.stderr, /exactly five/i);
});
