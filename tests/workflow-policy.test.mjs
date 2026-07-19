import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync('.github/workflows/build.yml', 'utf8');

test('checks upstream once every seven days and validates pull requests', () => {
  assert.match(workflow, /cron: "17 2 \* \* 0"/);
  assert.match(workflow, /^  pull_request:/m);
  assert.match(workflow, /^      publish:/m);
  assert.match(workflow, /github\.event_name == 'pull_request'/);
});

test('preserves every forced rebuild without racing its build identity', () => {
  assert.match(
    workflow,
    /github\.event_name == 'workflow_dispatch' && inputs\.force && format\('force-\{0\}', github\.run_id\)/,
  );
});

test('uses read-only permission until the isolated release job', () => {
  assert.match(workflow, /^permissions:\n  contents: read$/m);
  assert.match(workflow, /^  release:\n(?:.|\n)*?    permissions:\n      contents: write/m);
  assert.match(workflow, /needs: \[discover, build\]/);
  assert.match(workflow, /github\.event_name != 'pull_request'/);
  assert.match(workflow, /github\.ref == format\('refs\/heads\/\{0\}', github\.event\.repository\.default_branch\)/);
  assert.match(workflow, /inputs\.publish/);
});

test('runs every image and release-asset gate before artifact upload', () => {
  assert.match(workflow, /\.\/scripts\/verify-image\.sh/);
  assert.match(workflow, /\.\/scripts\/package-release\.sh/);
  assert.match(workflow, /\.\/scripts\/verify-release-assets\.sh/);
  assert.match(workflow, /validation-report\.json/);
  assert.match(workflow, /if-no-files-found: error/);
});

test('downloads and reverifies the artifact before immutable publishing', () => {
  assert.match(workflow, /actions\/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131/);
  assert.match(workflow, /^      - name: Reverify downloaded release assets$/m);
  assert.match(workflow, /gh release create "\$BUILD_TAG"/);
  assert.match(workflow, /gh release create "\$BUILD_TAG"[^\n]*\\\n(?:.|\n)*?--draft/);
  assert.match(workflow, /git\/refs/);
  assert.match(workflow, /--verify-tag/);
  assert.match(workflow, /gh release edit "\$BUILD_TAG"[^\n]*--draft=false/);
  assert.doesNotMatch(workflow, /--latest/);
  assert.doesNotMatch(workflow, /gh release upload|--clobber/);
});

test('pins all third-party actions to reviewed commits', () => {
  assert.match(workflow, /actions\/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0/);
  assert.match(workflow, /actions\/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e/);
  assert.match(workflow, /actions\/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/);
  assert.doesNotMatch(workflow, /uses: [^\n]+@v\d/);
});
