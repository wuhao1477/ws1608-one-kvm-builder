import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve('.');
const discover = path.join(root, 'scripts/discover-release.sh');
const upstreamRelease = JSON.stringify({
  draft: false,
  prerelease: false,
  tag_name: 'v260709',
  assets: [{
    name: 'one-kvm_0.2.4_armhf.deb',
    browser_download_url: 'https://example.invalid/one-kvm_0.2.4_armhf.deb',
    digest: 'sha256:abc123',
  }],
});

function runDiscover(releases, force = false) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-discover-'));
  const binDirectory = path.join(directory, 'bin');
  fs.mkdirSync(binDirectory);
  const fakeGh = path.join(binDirectory, 'gh');
  fs.writeFileSync(fakeGh, `#!/bin/sh
set -eu
if [ "$1" = api ]; then
  endpoint="$*"
  case "$endpoint" in
    *repos/mofeng-git/One-KVM/releases/latest*)
      printf '%s' "$UPSTREAM_JSON"
      ;;
    *'/releases?per_page=100'*)
      case "$endpoint" in
        *--slurp*) printf '[%s]' "$RELEASES_JSON" ;;
        *) printf '%s' "$RELEASES_JSON" ;;
      esac
      ;;
    *)
      exit 1
      ;;
  esac
else
  exit 1
fi
`);
  fs.chmodSync(fakeGh, 0o755);
  const outputFile = path.join(directory, 'output');
  const result = spawnSync(discover, [], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${binDirectory}:${process.env.PATH}`,
      GITHUB_OUTPUT: outputFile,
      GITHUB_REPOSITORY: 'wuhao1477/ws1608-one-kvm-builder',
      UPSTREAM_REPOSITORY: 'mofeng-git/One-KVM',
      UPSTREAM_JSON: upstreamRelease,
      RELEASES_JSON: JSON.stringify(releases),
      BUILD_TIME_UTC: '143015',
      FORCE_BUILD: String(force),
    },
  });
  assert.equal(result.status, 0, JSON.stringify({
    stderr: result.stderr,
    stdout: result.stdout,
    error: result.error?.message,
  }));
  const values = Object.fromEntries(
    fs.readFileSync(outputFile, 'utf8').trim().split('\n')
      .map((line) => line.split('=')),
  );
  return { values, stdout: result.stdout };
}

const assets = [
  { name: 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img', state: 'uploaded' },
  { name: 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img.xz', state: 'uploaded' },
  { name: 'SHA256SUMS', state: 'uploaded' },
  { name: 'manifest.json', state: 'uploaded' },
];

test('discovers a new upstream version with the short timestamp identity', () => {
  const { values } = runDiscover([]);
  assert.equal(values.changed, 'true');
  assert.equal(values.build_tag, 'ws1608-one-kvm-0.2.4-v260709-143015');
  assert.equal(values.build_stamp, '143015');
  assert.equal(values.image_name, assets[0].name);
  assert.equal(values.package_digest, 'abc123');
});

test('skips a valid new-format release for the same upstream tag', () => {
  const { values } = runDiscover([{
    draft: false,
    prerelease: false,
    tag_name: 'ws1608-one-kvm-0.2.4-v260709-143015',
    assets,
  }]);
  assert.equal(values.changed, 'false');
});

test('reports a new-format release before the legacy migration release', () => {
  const { values } = runDiscover([
    {
      draft: false,
      prerelease: false,
      tag_name: 'ws1608-one-kvm-v260709',
      assets,
    },
    {
      draft: false,
      prerelease: false,
      tag_name: 'ws1608-one-kvm-0.2.4-v260709-143015',
      assets,
    },
  ]);
  assert.equal(values.changed, 'false');
  assert.equal(values.existing_build_tag, 'ws1608-one-kvm-0.2.4-v260709-143015');
});

test('skips a valid legacy release during migration', () => {
  const { values } = runDiscover([{
    draft: false,
    prerelease: false,
    tag_name: 'ws1608-one-kvm-v260709',
    assets: [
      { name: 'One-KVM_0.2.4_Onecloud_trixie_6.12.28_HDMI-test.burn.img', state: 'uploaded' },
      { name: 'One-KVM_0.2.4_Onecloud_trixie_6.12.28_HDMI-test.burn.img.xz', state: 'uploaded' },
      { name: 'SHA256SUMS', state: 'uploaded' },
      { name: 'manifest.json', state: 'uploaded' },
    ],
  }]);
  assert.equal(values.changed, 'false');
});

test('does not count incomplete or draft releases as successful', () => {
  const { values } = runDiscover([{
    draft: true,
    prerelease: false,
    tag_name: 'ws1608-one-kvm-0.2.4-v260709-143015',
    assets: assets.slice(0, 2),
  }]);
  assert.equal(values.changed, 'true');
});

test('force mode rebuilds an already published upstream version', () => {
  const { values } = runDiscover([{
    draft: false,
    prerelease: false,
    tag_name: 'ws1608-one-kvm-0.2.4-v260709-143015',
    assets,
  }], true);
  assert.equal(values.changed, 'true');
  assert.equal(values.build_tag, 'ws1608-one-kvm-0.2.4-v260709-143015');
});
