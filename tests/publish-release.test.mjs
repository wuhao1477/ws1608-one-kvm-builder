import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const publishScript = path.resolve('scripts/publish-release.sh');
const imageName = 'One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img';

function hash(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function setup({ mismatch = false, existing = false } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-publish-'));
  const bin = path.join(directory, 'bin');
  fs.mkdirSync(bin);
  const artifact = path.join(directory, 'artifact');
  fs.mkdirSync(artifact);
  for (const name of [imageName, `${imageName}.xz`, 'SHA256SUMS', 'manifest.json']) {
    fs.writeFileSync(path.join(artifact, name), name);
  }
  const notes = path.join(directory, 'notes.md');
  fs.writeFileSync(notes, 'release notes');
  const assets = [imageName, `${imageName}.xz`, 'SHA256SUMS', 'manifest.json'];
  const remoteAssets = assets.map((name, index) => ({
    name,
    state: 'uploaded',
    digest: `sha256:${mismatch && index === 0 ? '0'.repeat(64) : hash(path.join(artifact, name))}`,
  }));
  const baseRelease = {
    tagName: 'ws1608-one-kvm-0.2.4-v260709-143015',
    isDraft: true,
    isPrerelease: false,
    assets: remoteAssets,
  };
  const draftPath = path.join(directory, 'draft.json');
  const publishedPath = path.join(directory, 'published.json');
  fs.writeFileSync(draftPath, JSON.stringify(baseRelease));
  fs.writeFileSync(publishedPath, JSON.stringify({ ...baseRelease, isDraft: false }));
  const fakeGh = path.join(bin, 'gh');
  fs.writeFileSync(fakeGh, `#!/bin/sh
set -eu
state_file="$STATE_FILE"
log="$LOG_FILE"
printf '%s\n' "$*" >> "$log"
if [ "$1" = api ]; then
  if [ "\${EXISTING_TAG:-false}" = true ]; then exit 0; fi
  exit 1
fi
[ "$1" = release ]
sub="$2"
if [ "$sub" = view ]; then
  case " $* " in
    *--json*)
      if [ "$(cat "$state_file")" = published ]; then cat "$PUBLISHED_JSON"; else cat "$DRAFT_JSON"; fi
      ;;
    *)
      if [ "\${EXISTING_RELEASE:-false}" = true ]; then exit 0; fi
      exit 1
      ;;
  esac
elif [ "$sub" = create ]; then
  printf '%s' draft > "$state_file"
elif [ "$sub" = edit ]; then
  printf '%s' published > "$state_file"
elif [ "$sub" = delete ]; then
  printf '%s' deleted > "$state_file"
fi
`);
  fs.chmodSync(fakeGh, 0o755);
  fs.writeFileSync(path.join(directory, 'state'), 'none');
  return {
    directory,
    artifact,
    notes,
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      STATE_FILE: path.join(directory, 'state'),
      LOG_FILE: path.join(directory, 'gh.log'),
      DRAFT_JSON: draftPath,
      PUBLISHED_JSON: publishedPath,
      GITHUB_REPOSITORY: 'wuhao1477/ws1608-one-kvm-builder',
      GITHUB_SHA: 'a'.repeat(40),
      BUILD_TAG: 'ws1608-one-kvm-0.2.4-v260709-143015',
      BUILD_STAMP: '143015',
      ONE_KVM_VERSION: '0.2.4',
      UPSTREAM_TAG: 'v260709',
      IMAGE_NAME: imageName,
      ARTIFACT_DIR: artifact,
      RELEASE_NOTES_FILE: notes,
      EXISTING_RELEASE: String(existing),
    },
  };
}

function run(options) {
  const setupData = setup(options);
  const result = spawnSync(publishScript, [], { cwd: path.resolve('.'), env: setupData.env, encoding: 'utf8' });
  const state = fs.readFileSync(path.join(setupData.directory, 'state'), 'utf8');
  const log = fs.readFileSync(path.join(setupData.directory, 'gh.log'), 'utf8');
  return { ...setupData, result, state, log };
}

test('publishes a draft only after remote asset digests match', () => {
  const run = runPublish({});
  assert.equal(run.result.status, 0, run.result.stderr);
  assert.equal(run.state, 'published');
  assert.match(run.log, /release create/);
  assert.match(run.log, /release edit/);
  assert.doesNotMatch(run.log, /release delete/);
});

test('deletes a newly created draft when a remote digest mismatches', () => {
  const run = runPublish({ mismatch: true });
  assert.notEqual(run.result.status, 0);
  assert.equal(run.state, 'deleted');
  assert.match(run.log, /release delete/);
});

test('refuses to overwrite an existing release', () => {
  const run = runPublish({ existing: true });
  assert.notEqual(run.result.status, 0);
  assert.equal(run.state, 'none');
  assert.doesNotMatch(run.log, /release create/);
});

function runPublish(options) {
  return run(options);
}
