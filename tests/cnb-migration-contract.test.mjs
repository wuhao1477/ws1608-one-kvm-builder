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
  assert.match(pipeline, /api_trigger_one-kvm-release/);
  assert.match(pipeline, /\$:\n[\s\S]*pull_request:/);
  assert.match(pipeline, /codex\/hcodec-\*/);
  assert.match(pipeline, /web_trigger_stable/);
  assert.match(pipeline, /web_trigger_hcodec/);
  assert.match(pipeline, /web_trigger_amlenc/);
  assert.doesNotMatch(pipeline, /main:\n\s+push:/);
  assert.doesNotMatch(pipeline, /codex\/amlenc-\*":\n\s+push:/);
});

test('maps GitHub workflow inputs to CNB Web Trigger inputs', () => {
  const triggers = read('.cnb/web_trigger.yml');

  for (const input of ['force', 'publish', 'prerelease', 'acknowledge_experimental']) {
    assert.match(triggers, new RegExp(`name: ${input}`));
  }
});

test('publishes releases through CNB and transfers candidate artifacts through the official attachment flow', () => {
  const release = read('scripts/cnb-publish-release.sh');
  const pipeline = read('.cnb.yml');
  const download = read('scripts/cnb-download-commit-assets.sh');

  assert.match(release, /post-release-asset-upload-url/);
  assert.match(release, /post-release-asset-upload-confirmation/);
  assert.match(release, /decodeURIComponent/);
  assert.match(pipeline, /cnbcool\/attachments:latest/);
  assert.match(pipeline, /ttl: 14/);
  assert.equal((pipeline.match(/FILES: ASSET_FILES/g) ?? []).length, 3);
  assert.doesNotMatch(pipeline, /ASSET_FILES: FILES/);
  assert.match(download, /commit-assets\/download/);
  assert.match(download, /application\/vnd\.cnb\.api\+json/);
  assert.equal(fs.existsSync('scripts/cnb-upload-commit-assets.sh'), false);
});

test('bootstraps Node.js before downloading CNB attachments', () => {
  const download = read('scripts/cnb-download-commit-assets.sh');

  assert.match(download, /source "\$ROOT_DIR\/scripts\/cnb-ci-env\.sh"/);
  assert.match(download, /encodeURIComponent/);
});

test('CNB discovery uses the CNB repository APIs instead of gh', () => {
  const script = read('scripts/cnb-discover-release.sh');

  assert.match(script, /cnb releases list-releases/);
  assert.match(script, /cnb git list-tags/);
  assert.doesNotMatch(script, /\bgh\s/);
});

test('CNB runner scripts bootstrap the CLI when the runner image does not include it', () => {
  const environment = read('scripts/cnb-ci-env.sh');
  const cli = read('scripts/cnb');

  assert.match(environment, /export PATH=/);
  assert.match(environment, /nodejs\.org\/dist/);
  assert.match(environment, /\.tar\.gz/);
  assert.match(environment, /CNB_NODE_VERSION/);
  assert.match(environment, /CNB_NODE_PREFIX:-\/tmp\/cnb-tools/);
  assert.match(environment, /go\.dev\/dl/);
  assert.match(environment, /CNB_GO_VERSION/);
  assert.match(environment, /CNB_GO_PREFIX:-\/tmp\/cnb-tools/);
  assert.match(environment, /sha256sum --check/);
  assert.doesNotMatch(environment, /ensure_go\n/);
  assert.match(cli, /CNB_API_ENDPOINT/);
  assert.match(cli, /Authorization: Bearer/);
  assert.match(cli, /post-release-asset-upload-confirmation/);
  assert.match(cli, /post-commit-asset-upload-confirmation/);
});

test('HCODEC runner creates its build workspace before downloading the base image', () => {
  const runner = read('scripts/cnb-run-hcodec.sh');

  assert.match(runner, /mkdir -p "\$ROOT_DIR\/\.build\/hcodec"/);
  assert.match(runner, /mkdir -p "\$ROOT_DIR\/out\/hcodec\/kernel"/);
});

test('keeps CNB publication and GitHub Actions available', () => {
  const pipeline = read('.cnb.yml');
  const scripts = `${read('scripts/cnb-discover-release.sh')}\n${read('scripts/cnb-publish-release.sh')}`;
  const stable = read('scripts/cnb-run-stable.sh');
  const finalize = read('scripts/cnb-finalize-stable.sh');
  const inner = read('scripts/cnb-run-stable-inner.sh');
  const githubBuild = read('.github/workflows/build.yml');
  const githubHcodec = read('.github/workflows/hcodec-candidate.yml');
  const githubAmlenc = read('.github/workflows/amlenc-experimental.yml');

  assert.match(stable, /scripts\/cnb-discover-release\.sh/);
  assert.match(finalize, /scripts\/cnb-publish-release\.sh/);
  assert.match(stable, /ensure_go/);
  assert.match(stable, /AMLIMG_GIT_PROXY/);
  assert.match(stable, /gh-proxy\.com/);
  assert.match(stable, /apt-get install -y binutils e2fsprogs file jq mtools qemu-user-static util-linux xz-utils/);
  assert.match(inner, /verify-release-assets\.sh/);
  for (const field of ['UPSTREAM_TAG', 'BUILD_TAG', 'BUILD_NUMBER', 'BUILD_REVISION', 'IMAGE_STEM', 'ONE_KVM_VERSION', 'PACKAGE_NAME', 'PACKAGE_URL', 'PACKAGE_DIGEST', 'BUILDER_COMMIT']) {
    assert.match(stable, new RegExp(`${field}=\\$\\{${field}:-`));
  }
  assert.doesNotMatch(scripts, /gh api|gh release/);
  for (const workflow of [githubBuild, githubHcodec, githubAmlenc]) {
    assert.match(workflow, /actions\/checkout@/);
    assert.match(workflow, /actions\/upload-artifact@/);
    assert.match(workflow, /actions\/download-artifact@/);
  }
});
