import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const workflow = fs.readFileSync('.github/workflows/build.yml', 'utf8');
const publishScript = fs.existsSync('scripts/publish-release.sh')
  ? fs.readFileSync('scripts/publish-release.sh', 'utf8')
  : '';
const releaseFlow = `${workflow}\n${publishScript}`;

test('re-downloads and verifies the workflow artifact before release', () => {
  assert.match(workflow, /actions\/download-artifact@v7/);
  assert.match(workflow, /Verify downloaded artifact/);
  assert.match(workflow, /Re-verify downloaded burn image/);
});

test('publishes only through a verified draft release', () => {
  assert.match(releaseFlow, /gh release create[\s\S]*--draft/);
  assert.match(releaseFlow, /asset\.digest|\.digest/);
  assert.match(releaseFlow, /--draft=false/);
  assert.match(releaseFlow, /--cleanup-tag/);
  assert.doesNotMatch(releaseFlow, /--clobber/);
});
