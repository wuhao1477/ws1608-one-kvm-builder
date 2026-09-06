import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync('.cnb.yml', 'utf8');
const stableWorkflow = workflow.slice(0, workflow.indexOf('\n$:'));
const contractWorkflow = workflow.slice(workflow.indexOf('\n$:'), workflow.indexOf('\n"codex/hcodec-*"'));

test('checks upstream once every seven days and validates pull requests', () => {
  assert.match(workflow, /"crontab: 17 2 \* \* 0":/);
  assert.match(workflow, /\$:\n\s+pull_request:/);
  assert.match(workflow, /api_trigger_one-kvm-release/);
  assert.match(workflow, /web_trigger_stable/);
});

test('preserves every forced rebuild without racing its build identity', () => {
  assert.match(workflow, /FORCE_BUILD: \$force/);
  assert.match(workflow, /lock:\n\s+key: ws1608-stable-release/);
});

test('keeps stable publication isolated from PR checks', () => {
  assert.match(stableWorkflow, /crontab: 17 2 \* \* 0/);
  assert.match(contractWorkflow, /PUBLISH: "false"/);
  assert.match(workflow, /PUBLISH: \$publish/);
  assert.match(workflow, /RELEASE_PRERELEASE: \$prerelease/);
});

test('runs every image and release-asset gate before CNB publication', () => {
  const script = fs.readFileSync('scripts/cnb-run-stable.sh', 'utf8');
  assert.match(script, /build-image\.sh/);
  assert.match(script, /verify-image\.sh/);
  assert.match(script, /package-release\.sh/);
  assert.match(script, /verify-release-assets\.sh/);
  assert.match(script, /cnb-publish-release\.sh/);
});

test('installs the FAT image tooling required for boot-console validation', () => {
  assert.match(fs.readFileSync('scripts/cnb-run-stable.sh', 'utf8'), /build-tools\.sh/);
});

test('uploads and reverifies immutable assets through CNB', () => {
  const script = fs.readFileSync('scripts/cnb-publish-release.sh', 'utf8');
  assert.match(script, /post-release-asset-upload-url/);
  assert.match(script, /post-release-asset-upload-confirmation/);
  assert.match(script, /get-release-by-tag/);
  assert.match(script, /hash_value/);
});

test('does not retain active GitHub Actions entrypoints', () => {
  for (const file of [
    '.github/workflows/build.yml',
    '.github/workflows/hcodec-candidate.yml',
    '.github/workflows/amlenc-experimental.yml',
  ]) assert.equal(fs.existsSync(file), false, file);
});
