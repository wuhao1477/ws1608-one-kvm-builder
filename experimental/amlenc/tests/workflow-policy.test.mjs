import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflowPath = '.cnb.yml';

test('keeps AMLENC builds isolated from the stable image workflow', () => {
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  const runner = fs.readFileSync('scripts/cnb-run-amlenc.sh', 'utf8');

  assert.match(workflow, /"codex\/amlenc-\*":/);
  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /web_trigger_amlenc/);
  assert.doesNotMatch(workflow, /schedule:|repository_dispatch:/);
  for (const script of [
    'verify-source-locks\.mjs', 'verify-stable-chain\.sh', 'build-kernel\.sh',
    'build-libvpcodec\.sh', 'build-diagnostic-image\.sh', 'build-one-kvm\.sh',
    'verify-one-kvm\.sh', 'build-burn-image\.sh', 'verify-burn-release\.sh',
  ]) assert.match(runner, new RegExp(script));
  assert.match(runner, /ssh-keygen -q -t ed25519 -N ''/);
  assert.match(runner, /DOCKER_BUILDKIT=1/);
  assert.match(runner, /gcc-arm-linux-gnueabihf/);
  assert.match(runner, /qemu-user-static/);
  assert.match(runner, /hardware_encoder_tested/);
  assert.match(runner, /stable_channel_modified/);
  assert.match(runner, /ws1608-amlenc-exp-/);
  assert.doesNotMatch(runner, /gh release create/);
});

test('publishes an explicitly acknowledged immutable experimental prerelease', () => {
  const triggers = fs.readFileSync('.cnb/web_trigger.yml', 'utf8');
  const runner = fs.readFileSync('scripts/cnb-run-amlenc.sh', 'utf8');
  assert.match(triggers, /publish:/);
  assert.match(triggers, /acknowledge_experimental:/);
  assert.match(runner, /PUBLISH:-false/);
  assert.match(runner, /ACKNOWLEDGE_EXPERIMENTAL:-false/);
  assert.match(runner, /RELEASE_PRERELEASE=true/);
  assert.match(runner, /cnb-publish-release\.sh/);
  assert.doesNotMatch(runner, /--clobber|--latest/);
});
