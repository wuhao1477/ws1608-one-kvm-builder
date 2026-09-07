import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const publishScript = path.resolve('scripts/cnb-publish-release.sh');
const buildTag = 'ws1608-one-kvm-0.2.4-v260709-b014001';
const imageName = 'One-KVM_0.2.4-v260709-b014001_Onecloud_trixie_6.12.28-HDMI-test.burn.img';

function setup({ existing = false, prerelease = false, failUpload = false } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-cnb-publish-'));
  const bin = path.join(directory, 'bin');
  const artifact = path.join(directory, 'artifact');
  fs.mkdirSync(bin);
  fs.mkdirSync(artifact);
  const assetNames = [imageName, `${imageName}.xz`, 'SHA256SUMS', 'manifest.json', 'validation-report.json'];
  for (const name of assetNames) fs.writeFileSync(path.join(artifact, name), name);
  const notes = path.join(directory, 'notes.md');
  fs.writeFileSync(notes, 'release notes\n');
  const state = path.join(directory, 'state');
  const assets = path.join(directory, 'assets');
  fs.writeFileSync(state, existing ? 'existing' : 'none');
  fs.writeFileSync(assets, '');
  const release = path.join(directory, 'release.json');
  fs.writeFileSync(release, JSON.stringify({ id: '101', tag_name: buildTag, draft: false, prerelease, assets: [] }));
  const api = path.join(bin, 'cnb');
  fs.writeFileSync(api, `#!/bin/sh
set -eu
state="$STATE_FILE"
release_file="$RELEASE_FILE"
assets_file="$ASSETS_FILE"
case "$1:$2" in
  releases:get-release-by-tag)
    if [ "$(cat "$state")" = existing ]; then
      printf '{"status":200,"data":'
      cat "$release_file"
      printf '}\\n'
    elif [ "$(cat "$state")" = published ]; then
      printf '{"status":200,"data":{"id":"101","draft":false,"prerelease":%s,"assets":[' "$RELEASE_PRERELEASE"
      separator=
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        digest=$(sha256sum "$RELEASE_ASSET_DIR/$name" | awk '{print $1}')
        printf '%s{"name":"%s","hash_value":"%s"}' "$separator" "$name" "$digest"
        separator=,
      done < "$assets_file"
      printf ']}}\\n'
    else
      printf '{"status":404,"data":{"errmsg":"not found"}}\\n'
    fi
    ;;
  releases:post-release)
    printf '%s' created >"$state"
    : >"$assets_file"
    printf '{"status":201,"data":{"id":"101"}}\\n'
    ;;
  releases:post-release-asset-upload-url)
    [ "$FAIL_UPLOAD" != true ] || exit 1
    previous=
    name=
    for argument in "$@"; do
      if [ "$previous" = --asset-name ]; then name="$argument"; previous=; continue; fi
      [ "$argument" = --asset-name ] && previous=--asset-name
    done
    printf '%s\\n' "$name" >>"$assets_file"
    printf '{"status":201,"data":{"upload_url":"https://upload.invalid/file","verify_url":"https://api.cnb.cool/repo/-/releases/101/asset-upload-confirmation/token/path"}}\\n'
    ;;
  releases:post-release-asset-upload-confirmation)
    printf '%s' confirmed >"$state"
    ;;
  releases:patch-release)
    printf '%s' published >"$state"
    ;;
  releases:delete-release)
    printf '%s' none >"$state"
    : >"$assets_file"
    ;;
  git:delete-tag)
    printf '%s' none >"$state"
    ;;
  *) exit 2 ;;
esac
`);
  fs.chmodSync(api, 0o755);
  const curl = path.join(bin, 'curl');
  fs.writeFileSync(curl, '#!/bin/sh\nexit 0\n');
  fs.chmodSync(curl, 0o755);
  return {
    directory,
    state,
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      STATE_FILE: state,
      RELEASE_FILE: release,
      ASSETS_FILE: assets,
      FAIL_UPLOAD: String(failUpload),
      RELEASE_ASSET_DIR: artifact,
      CNB_REPO_SLUG: 'wuhao1477/ws1608-one-kvm-builder',
      RELEASE_TAG: buildTag,
      RELEASE_NAME: 'test release',
      RELEASE_COMMIT: 'a'.repeat(40),
      RELEASE_NOTES_FILE: notes,
      RELEASE_PRERELEASE: String(prerelease),
      RELEASE_LATEST: 'false',
    },
  };
}

function run(options) {
  const data = setup(options);
  const result = spawnSync(publishScript, [], { cwd: process.cwd(), env: data.env, encoding: 'utf8' });
  return { ...data, result, state: fs.readFileSync(data.state, 'utf8') };
}

test('publishes a release with every asset and finalizes it', () => {
  const result = run();
  assert.equal(result.result.status, 0, `${result.result.stdout}\n${result.result.stderr}`);
  assert.equal(result.state, 'published');
});

test('refuses to overwrite an existing release', () => {
  const result = run({ existing: true });
  assert.notEqual(result.result.status, 0);
  assert.equal(result.state, 'existing');
});

test('removes a partially created release after upload failure', () => {
  const result = run({ failUpload: true });
  assert.notEqual(result.result.status, 0);
  assert.equal(result.state, 'none');
});

test('preserves prerelease selection', () => {
  const result = run({ prerelease: true });
  assert.equal(result.result.status, 0, `${result.result.stdout}\n${result.result.stderr}`);
  assert.equal(result.state, 'published');
});
