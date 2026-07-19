import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const verifier = path.resolve('scripts/verify-artifacts.mjs');

function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

function makeArtifact() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-artifact-'));
  const imageName = 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img';
  const imagePath = path.join(directory, imageName);
  const xzPath = `${imagePath}.xz`;
  fs.writeFileSync(imagePath, Buffer.from('synthetic burn image for verifier tests\n'));
  fs.writeFileSync(xzPath, execFileSync('xz', ['-c', imagePath]));
  const imageHash = sha256(imagePath);
  const xzHash = sha256(xzPath);
  fs.writeFileSync(path.join(directory, 'SHA256SUMS'), `${imageHash}  ${imageName}\n${xzHash}  ${imageName}.xz\n`);
  fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify({
    image: imageName,
    image_xz: `${imageName}.xz`,
    image_sha256: imageHash,
    image_xz_sha256: xzHash,
    build_tag: 'ws1608-one-kvm-0.2.4-v260709-143015',
    one_kvm_version: '0.2.4',
  }, null, 2));
  return { directory, imageName, imagePath, xzPath };
}

function runVerifier(artifact) {
  return spawnSync(process.execPath, [
    verifier,
    artifact.directory,
    artifact.imageName,
    JSON.stringify({
      build_tag: 'ws1608-one-kvm-0.2.4-v260709-143015',
      one_kvm_version: '0.2.4',
    }),
  ], { encoding: 'utf8' });
}

test('accepts a complete artifact and verifies the xz byte round-trip', () => {
  const artifact = makeArtifact();
  const result = runVerifier(artifact);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /verified-artifacts/);
});

test('rejects a compressed artifact changed after SHA256SUMS was written', () => {
  const artifact = makeArtifact();
  fs.appendFileSync(artifact.xzPath, Buffer.from('tampered'));
  const result = runVerifier(artifact);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /SHA256SUMS|digest/i);
});

test('rejects undeclared intermediate files', () => {
  const artifact = makeArtifact();
  fs.writeFileSync(path.join(artifact.directory, 'unexpected.sha256'), 'wrong');
  const result = runVerifier(artifact);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unexpected|exactly/i);
});

