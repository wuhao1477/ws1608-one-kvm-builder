import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const builderPath = 'experimental/amlenc/scripts/build-burn-image.sh';
const verifierPath = 'experimental/amlenc/scripts/verify-burn-image.sh';
const packagerPath = 'experimental/amlenc/scripts/package-burn-release.sh';
const workflowPath = '.github/workflows/amlenc-experimental.yml';

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
  const workflow = read(workflowPath);
  assert.match(workflow, /Build experimental burn image/);
  assert.match(workflow, /Verify experimental burn image/);
  assert.match(workflow, /Package experimental burn metadata/);
  assert.match(workflow, /hardware_encoder_tested.*false|hardware_encoder_tested.*true/s);
  const buildIndex = workflow.indexOf('Build experimental burn image');
  const verifyIndex = workflow.indexOf('Verify experimental burn image');
  const uploadIndex = workflow.indexOf('Upload experimental build metadata');
  assert.ok(buildIndex >= 0 && verifyIndex > buildIndex && uploadIndex > verifyIndex);
});

test('does not create a formal release from an unverified burn image', () => {
  const workflow = read(workflowPath);
  assert.doesNotMatch(workflow, /publish-burn-release|gh release create.*amlenc/i);
  assert.match(workflow, /hardware_encoder_tested.*false|local-test-only/s);
});
