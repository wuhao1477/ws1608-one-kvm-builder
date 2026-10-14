import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync('.github/workflows/build-base.yml', 'utf8');
const base = fs.readFileSync('config/base.env', 'utf8');

test('uses the hardware-verified Trixie base image as the only burn artifact', () => {
  assert.match(workflow, /source config\/base\.env/);
  assert.match(workflow, /BASE_IMAGE_URL/);
  assert.match(workflow, /BASE_IMAGE_SHA256/);
  assert.match(workflow, /xz -dc/);
  assert.match(base, /BASE_RELEASE_TAG=base-20260804-consolefix/);
  assert.match(base, /BASE_KERNEL=6\.12\.28-current-meson/);
  assert.match(base, /BASE_IMAGE_SHA256=[0-9a-f]{64}/);
  assert.doesNotMatch(workflow, /matrix:/);
  assert.doesNotMatch(workflow, /strategy:/);
  assert.doesNotMatch(workflow, /bookworm|noble|sid|server|cli/);
});

test('does not rebuild an unverified kernel or publish a One-KVM image', () => {
  assert.doesNotMatch(workflow, /compile\.sh build/);
  assert.doesNotMatch(workflow, /BUILD_MINIMAL/);
  assert.doesNotMatch(workflow, /publish-release\.sh/);
});
