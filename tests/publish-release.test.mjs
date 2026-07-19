import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const publishScript = path.resolve('scripts/publish-release.sh');
const buildTag = 'ws1608-one-kvm-0.2.4-v260709-b014001';
const imageName = 'One-KVM_0.2.4-v260709-b014001_Onecloud_trixie_6.12.28_HDMI-test.burn.img';

function hash(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function setup({
  mismatch = false,
  incomplete = false,
  existing = false,
  existingTag = false,
  failCreate = false,
  failUpload = false,
  bodyMismatch = false,
  duplicateBody = false,
} = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-publish-'));
  const bin = path.join(directory, 'bin');
  const artifact = path.join(directory, 'artifact');
  fs.mkdirSync(bin);
  fs.mkdirSync(artifact);
  const assetNames = [
    imageName,
    `${imageName}.xz`,
    'SHA256SUMS',
    'manifest.json',
    'validation-report.json',
  ];
  for (const name of assetNames) fs.writeFileSync(path.join(artifact, name), name);
  const notes = path.join(directory, 'notes.md');
  fs.writeFileSync(notes, 'release notes\n');
  const remoteAssets = assetNames.map((name, index) => ({
    name,
    state: 'uploaded',
    digest: `sha256:${mismatch && index === 0 ? '0'.repeat(64) : hash(path.join(artifact, name))}`,
  }));
  if (incomplete) remoteAssets.pop();
  const packageDigest = 'b'.repeat(64);
  const builderCommit = 'a'.repeat(40);
  const bodyLines = [
    'one_kvm_version=0.2.4',
    'one_kvm_release=v260709',
    `package_sha256=${packageDigest}`,
    'build_number=14001',
    'build_revision=b014001',
    `build_tag=${bodyMismatch ? 'wrong-tag' : buildTag}`,
    `builder_commit=${builderCommit}`,
    `image_name=${imageName}`,
    `compressed_image_name=${imageName}.xz`,
    'checksums_name=SHA256SUMS',
    'manifest_name=manifest.json',
    'validation_report_name=validation-report.json',
    `image_sha256=${hash(path.join(artifact, imageName))}`,
    `compressed_image_sha256=${hash(path.join(artifact, `${imageName}.xz`))}`,
    `checksums_sha256=${hash(path.join(artifact, 'SHA256SUMS'))}`,
    `manifest_sha256=${hash(path.join(artifact, 'manifest.json'))}`,
    `validation_report_sha256=${hash(path.join(artifact, 'validation-report.json'))}`,
  ];
  if (duplicateBody) bodyLines.unshift('build_tag=wrong-tag');
  const body = bodyLines.join('\n');
  const baseRelease = {
    tagName: buildTag,
    isDraft: true,
    isPrerelease: false,
    assets: remoteAssets,
    body,
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
if [ "$1" = release ]; then
  case "$2" in
    view)
      case " $* " in
        *" --json "*)
          if [ "$(cat "$state_file")" = published ]; then cat "$PUBLISHED_JSON"; else cat "$DRAFT_JSON"; fi
          ;;
        *)
          [ "$EXISTING_RELEASE" = true ]
          ;;
      esac
      ;;
    upload)
      [ "$FAIL_UPLOAD" != true ] || exit 1
      printf '%s' uploaded > "$state_file"
      ;;
    *) exit 2 ;;
  esac
  exit
fi
[ "$1" = api ] || exit 2
method=GET
endpoint=''
previous=''
for argument in "$@"; do
  if [ "$previous" = --method ]; then method="$argument"; previous=''; continue; fi
  if [ "$argument" = --method ]; then previous=--method; continue; fi
  case "$argument" in
    repos/*) endpoint="$argument" ;;
  esac
done
case "$method:$endpoint" in
  GET:*/git/ref/tags/*)
    if [ "$EXISTING_TAG" = true ] || [ "$(cat "$state_file")" != none ]; then
      printf '{"object":{"sha":"%s"}}\n' "$BUILDER_COMMIT"
    else
      exit 1
    fi
    ;;
  POST:*/git/refs)
    [ "$EXISTING_TAG" != true ] || exit 1
    printf '%s' tag > "$state_file"
    printf '{"object":{"sha":"%s"}}\n' "$BUILDER_COMMIT"
    ;;
  POST:*/releases)
    [ "$FAIL_RELEASE_CREATE" != true ] || exit 1
    printf '%s' draft > "$state_file"
    printf '{"id":101}\n'
    ;;
  PATCH:*/releases/101)
    printf '%s' published > "$state_file"
    printf '{}\n'
    ;;
  DELETE:*/releases/101)
    printf '%s' release-deleted > "$state_file"
    ;;
  DELETE:*/git/refs/tags/*)
    printf '%s' deleted > "$state_file"
    ;;
  *) exit 2 ;;
esac
`);
  fs.chmodSync(fakeGh, 0o755);
  fs.writeFileSync(path.join(directory, 'state'), 'none');
  return {
    directory,
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      STATE_FILE: path.join(directory, 'state'),
      LOG_FILE: path.join(directory, 'gh.log'),
      DRAFT_JSON: draftPath,
      PUBLISHED_JSON: publishedPath,
      GITHUB_REPOSITORY: 'wuhao1477/ws1608-one-kvm-builder',
      BUILD_TAG: buildTag,
      BUILD_NUMBER: '14001',
      BUILD_REVISION: 'b014001',
      BUILDER_COMMIT: builderCommit,
      ONE_KVM_VERSION: '0.2.4',
      UPSTREAM_TAG: 'v260709',
      PACKAGE_DIGEST: packageDigest,
      IMAGE_NAME: imageName,
      ARTIFACT_DIR: artifact,
      RELEASE_NOTES_FILE: notes,
      EXISTING_RELEASE: String(existing),
      EXISTING_TAG: String(existingTag),
      FAIL_RELEASE_CREATE: String(failCreate),
      FAIL_UPLOAD: String(failUpload),
    },
  };
}

function run(options) {
  const data = setup(options);
  const result = spawnSync(publishScript, [], {
    cwd: path.resolve('.'),
    env: data.env,
    encoding: 'utf8',
  });
  return {
    ...data,
    result,
    state: fs.readFileSync(path.join(data.directory, 'state'), 'utf8'),
    log: fs.readFileSync(path.join(data.directory, 'gh.log'), 'utf8'),
  };
}

test('publishes exactly five verified assets from an atomically reserved tag', () => {
  const result = run();
  assert.equal(result.result.status, 0, result.result.stderr);
  assert.equal(result.state, 'published');
  assert.match(result.log, /api --method POST repos\/wuhao1477\/ws1608-one-kvm-builder\/git\/refs/);
  assert.match(result.log, /release upload/);
  assert.match(result.log, /validation-report\.json/);
  assert.match(result.log, /api --method PATCH repos\/wuhao1477\/ws1608-one-kvm-builder\/releases\/101/);
  assert.doesNotMatch(result.log, /--clobber|--latest| --method DELETE /);
});

test('removes only the created release and tag when remote verification fails', () => {
  for (const options of [
    { mismatch: true },
    { incomplete: true },
    { failUpload: true },
    { bodyMismatch: true },
    { duplicateBody: true },
  ]) {
    const result = run(options);
    assert.notEqual(result.result.status, 0);
    assert.equal(result.state, 'deleted');
    assert.match(result.log, /api --method DELETE repos\/wuhao1477\/ws1608-one-kvm-builder\/releases\/101/);
    assert.match(result.log, /api --method DELETE repos\/wuhao1477\/ws1608-one-kvm-builder\/git\/refs\/tags/);
  }
});

test('does not delete a release it did not create', () => {
  const result = run({ existing: true });
  assert.notEqual(result.result.status, 0);
  assert.equal(result.state, 'none');
  assert.doesNotMatch(result.log, / --method DELETE |release upload/);
});

test('cleans up only its tag when release creation fails', () => {
  const result = run({ failCreate: true });
  assert.notEqual(result.result.status, 0);
  assert.equal(result.state, 'deleted');
  assert.doesNotMatch(result.log, /releases\/101/);
  assert.match(result.log, /git\/refs\/tags/);
});

test('refuses an existing tag before creating any release', () => {
  const result = run({ existingTag: true });
  assert.notEqual(result.result.status, 0);
  assert.equal(result.state, 'none');
  assert.doesNotMatch(result.log, /release upload|POST repos\/wuhao1477\/ws1608-one-kvm-builder\/releases/);
});
