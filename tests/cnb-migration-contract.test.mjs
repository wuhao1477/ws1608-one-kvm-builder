import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

test('defines CNB pipelines for stable, candidate, PR, scheduled, and manual builds', () => {
  const pipeline = read('.cnb.yml');

  assert.match(pipeline, /main:\n/);
  assert.match(pipeline, /crontab: 17 2 \* \* 0/);
  assert.match(pipeline, /pull_request:/);
  assert.match(pipeline, /codex\/hcodec-\*/);
  assert.match(pipeline, /web_trigger_stable/);
  assert.match(pipeline, /web_trigger_hcodec/);
  assert.match(pipeline, /web_trigger_amlenc/);
});

test('maps GitHub workflow inputs to CNB Web Trigger inputs', () => {
  const triggers = read('.cnb/web_trigger.yml');

  for (const input of ['force', 'publish', 'prerelease', 'acknowledge_experimental']) {
    assert.match(triggers, new RegExp(`name: ${input}`));
  }
});

test('publishes release assets through CNB and candidate assets through commit storage', () => {
  const release = read('scripts/cnb-publish-release.sh');
  const candidate = read('scripts/cnb-upload-commit-assets.sh');

  assert.match(release, /post-release-asset-upload-url/);
  assert.match(release, /post-release-asset-upload-confirmation/);
  assert.match(candidate, /post-commit-asset-upload-url/);
  assert.match(candidate, /post-commit-asset-upload-confirmation/);
  assert.match(candidate, /TTL=\$\{CNB_ASSET_TTL:-14\}/);
});

test('CNB discovery uses the CNB repository APIs instead of gh', () => {
  const script = read('scripts/cnb-discover-release.sh');

  assert.match(script, /cnb releases list-releases/);
  assert.match(script, /cnb git list-tags/);
  assert.doesNotMatch(script, /\bgh\s/);
});

test('stable CNB publication is independent of GitHub Actions', () => {
  const pipeline = read('.cnb.yml');
  const scripts = `${read('scripts/cnb-discover-release.sh')}\n${read('scripts/cnb-publish-release.sh')}`;

  assert.match(read('scripts/cnb-run-stable.sh'), /scripts\/cnb-discover-release\.sh/);
  assert.match(read('scripts/cnb-run-stable.sh'), /scripts\/cnb-publish-release\.sh/);
  assert.doesNotMatch(scripts, /gh api|gh release/);
});
