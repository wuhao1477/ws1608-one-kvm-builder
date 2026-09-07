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
const workflowPath = '.cnb.yml';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

test('defines an isolated burn image build and verification chain', () => {
  assert.equal(fs.existsSync(builderPath), true, 'burn image builder is required');
  assert.equal(fs.existsSync(verifierPath), true, 'burn image verifier is required');
  assert.equal(fs.existsSync(packagerPath), true, 'burn release packager is required');
  const builder = read(builderPath);
  const verifier = read(verifierPath);
  const packager = read(packagerPath);
  assert.match(builder, /AmlImg/);
  assert.match(builder, /raw-to-sparse\.mjs/);
  assert.match(builder, /one_kvm/);
  assert.match(builder, /hardware_encoder_tested/);
  assert.match(verifier, /AmlImg.*unpack|unpack.*AmlImg/s);
  assert.match(verifier, /sha1sum/);
  assert.match(verifier, /e2fsck/);
  assert.match(verifier, /one[-_]kvm/);
  assert.match(verifier, /hardware_encoder_tested/);
  assert.match(packager, /xz/);
  assert.match(packager, /SHA256SUMS/);
});

test('runs burn image gates before metadata upload and keeps hardware gate explicit', () => {
  const runner = read('scripts/cnb-run-amlenc.sh');
  const pipeline = read(workflowPath);
  assert.match(runner, /build-burn-image\.sh/);
  assert.match(runner, /verify-burn-image\.sh/);
  assert.match(runner, /package-burn-release\.sh/);
  assert.match(runner, /verify-burn-release\.sh/);
  assert.match(pipeline, /image: cnbcool\/attachments:latest/);
  assert.match(pipeline, /out\/amlenc\/burn\/\*/);
  assert.match(pipeline, /ttl: 14/);
  assert.match(pipeline, /cnb-download-commit-assets\.sh/);
  assert.match(pipeline, /CNB_PULL_REQUEST/);
  assert.match(pipeline, /cnb-finalize-amlenc\.sh .* local/);
  assert.doesNotMatch(runner, /cnb-upload-commit-assets\.sh/);
});

test('keeps untested hardware status explicit in the experimental prerelease', () => {
  const runner = read('scripts/cnb-run-amlenc.sh');
  const finalize = read('scripts/cnb-finalize-amlenc.sh');
  assert.match(finalize, /RELEASE_PRERELEASE=true/);
  assert.match(finalize, /ACKNOWLEDGE_EXPERIMENTAL/);
  assert.match(runner, /ACKNOWLEDGE_EXPERIMENTAL/);
  assert.match(runner, /hardware_encoder_tested/);
  assert.match(runner, /hardware_boot_tested/);
});

test('verifies exactly five packaged burn release assets', (t) => {
  assert.equal(fs.existsSync(releaseVerifierPath), true, 'burn release verifier is required');
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-burn-release-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const imageName = 'WS1608-AMLENC_0.2.6+ws1608amlenc.run-1-1_Onecloud_bullseye_3.10.107.burn.img';
  const image = path.join(fixture, imageName);
  fs.writeFileSync(image, 'burn-image-fixture');
  assert.equal(spawnSync('xz', ['-k', image], { encoding: 'utf8' }).status, 0);
  const digest = (file) => spawnSync('sha256sum', [file], { encoding: 'utf8' }).stdout.split(/\s+/)[0];
  const manifest = {
    schema: 1,
    kind: 'ws1608-amlenc-burn-image',
    image_name: imageName,
    image_sha256: digest(image),
    one_kvm: { version: '0.2.6+ws1608amlenc.run-1-1', sha256: 'a'.repeat(64) },
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
