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
  const inner = fs.readFileSync('scripts/cnb-run-stable-inner.sh', 'utf8');
  const finalize = fs.readFileSync('scripts/cnb-finalize-stable.sh', 'utf8');
  assert.match(script, /docker run --rm --privileged/);
  assert.match(script, /seccomp=unconfined/);
  assert.match(script, /systempaths=unconfined/);
  assert.match(script, /volume \/sys:\/sys:ro/);
  assert.match(script, /device \/dev\/loop-control/);
  assert.match(script, /device-cgroup-rule='b 7:\* rmw'/);
  assert.match(script, /mknod -m 660.*\/dev\/loop/);
  assert.match(script, /losetup -f/);
  assert.match(script, /device \/dev\/fuse/);
  assert.match(script, /apt-get install -y binutils e2fsprogs file fuse2fs fuse3/);
  assert.match(script, /cnb-run-stable-inner\.sh/);
  assert.match(script, /AMLIMG_BIN=\$\(container_path/);
  assert.match(script, /VALIDATION_REPORT=\$\(container_path/);
  for (const gate of ['build-image\.sh', 'verify-image\.sh', 'package-release\.sh', 'verify-release-assets\.sh']) {
    assert.match(inner, new RegExp(gate));
  }
  assert.match(finalize, /cnb-publish-release\.sh/);
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

test('uses official attachment upload and independent download verification for artifacts', () => {
  const pipeline = fs.readFileSync('.cnb.yml', 'utf8');
  const stable = fs.readFileSync('scripts/cnb-run-stable.sh', 'utf8');
  const inner = fs.readFileSync('scripts/cnb-run-stable-inner.sh', 'utf8');
  const download = fs.readFileSync('scripts/cnb-download-commit-assets.sh', 'utf8');
  const finalize = fs.readFileSync('scripts/cnb-finalize-stable.sh', 'utf8');

  assert.match(pipeline, /image: cnbcool\/attachments:latest/);
  assert.match(pipeline, /ASSET_FILES: FILES/);
  assert.match(pipeline, /ttl: 14/);
  assert.match(pipeline, /CNB_PULL_REQUEST/);
  assert.match(pipeline, /cnb-download-commit-assets\.sh/);
  assert.match(stable, /context\.env/);
  assert.doesNotMatch(stable, /cnb-upload-commit-assets\.sh/);
  assert.doesNotMatch(inner, /pr-uploaded|CNB_PULL_REQUEST/);
  assert.match(download, /cmp/);
  assert.match(finalize, /verify-release-assets\.sh/);
  assert.match(finalize, /cnb-publish-release\.sh/);
  assert.match(finalize, /local/);
});

test('retains GitHub Actions workflows alongside CNB', () => {
  for (const file of [
    '.github/workflows/build.yml',
    '.github/workflows/hcodec-candidate.yml',
    '.github/workflows/amlenc-experimental.yml',
  ]) {
    assert.equal(fs.existsSync(file), true, file);
    const workflow = fs.readFileSync(file, 'utf8');
    assert.match(workflow, /actions\/checkout@/);
    assert.match(workflow, /actions\/upload-artifact@/);
    assert.match(workflow, /actions\/download-artifact@/);
  }
});
