import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { discoverRelease } from '../scripts/lib/release-discovery.mjs';

const DIGEST_A = 'a'.repeat(64);
const DIGEST_B = 'b'.repeat(64);

function upstreamRelease(digest = DIGEST_A) {
  return {
    draft: false,
    prerelease: false,
    tag_name: 'v260709',
    assets: [
      {
        name: 'one-kvm_0.2.4_amd64.deb',
        browser_download_url: 'https://example.invalid/one-kvm_0.2.4_amd64.deb',
        digest: `sha256:${'c'.repeat(64)}`,
      },
      {
        name: 'one-kvm_0.2.4_armhf.deb',
        browser_download_url: 'https://example.invalid/one-kvm_0.2.4_armhf.deb',
        digest: digest ? `sha256:${digest}` : null,
      },
    ],
  };
}

function publishedBuild({ buildNumber = 1, digest = DIGEST_A, draft = false } = {}) {
  const revision = `b${String(buildNumber).padStart(3, '0')}`;
  const buildTag = `ws1608-one-kvm-0.2.4-v260709-${revision}`;
  return {
    draft,
    prerelease: false,
    tag_name: buildTag,
    published_at: `2026-07-${String(19 + buildNumber).padStart(2, '0')}T00:00:00Z`,
    body: [
      'one_kvm_version=0.2.4',
      'one_kvm_release=v260709',
      `package_sha256=${digest}`,
      `build_number=${buildNumber}`,
      `build_tag=${buildTag}`,
    ].join('\n'),
  };
}

test('allocates b001 with a readable One-KVM version for a new input', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    existingReleases: [],
    forceBuild: false,
  });

  assert.equal(result.changed, true);
  assert.equal(result.releaseTag, 'v260709');
  assert.equal(result.oneKvmVersion, '0.2.4');
  assert.equal(result.packageDigest, DIGEST_A);
  assert.equal(result.buildNumber, 1);
  assert.equal(result.buildRevision, 'b001');
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b001');
});

test('skips a published upstream tag and package digest', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    existingReleases: [publishedBuild()],
    forceBuild: false,
  });

  assert.equal(result.changed, false);
  assert.equal(result.buildNumber, 1);
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b001');
});

test('force allocates the next immutable build sequence', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    existingReleases: [publishedBuild(), publishedBuild({ buildNumber: 2 })],
    forceBuild: true,
  });

  assert.equal(result.changed, true);
  assert.equal(result.buildNumber, 3);
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b003');
});

test('parallel workflow runs receive distinct immutable build identities', () => {
  const first = discoverRelease({
    upstreamRelease: upstreamRelease(),
    forceBuild: true,
    workflowRunNumber: 14,
    workflowRunAttempt: 1,
  });
  const second = discoverRelease({
    upstreamRelease: upstreamRelease(),
    forceBuild: true,
    workflowRunNumber: 15,
    workflowRunAttempt: 1,
  });

  assert.equal(first.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b014001');
  assert.equal(second.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b015001');
});

test('a workflow rerun attempt receives a new immutable build identity', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    forceBuild: true,
    workflowRunNumber: 14,
    workflowRunAttempt: 2,
  });

  assert.equal(result.buildNumber, 14002);
  assert.equal(result.buildRevision, 'b014002');
});

test('a replaced Deb digest allocates a new build for the same upstream tag', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(DIGEST_B),
    existingReleases: [publishedBuild()],
    forceBuild: false,
  });

  assert.equal(result.changed, true);
  assert.equal(result.packageDigest, DIGEST_B);
  assert.equal(result.buildNumber, 2);
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b002');
});

test('a failed draft reserves its build sequence but does not suppress a rebuild', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    existingReleases: [publishedBuild({ draft: true })],
    forceBuild: false,
  });

  assert.equal(result.changed, true);
  assert.equal(result.buildNumber, 2);
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b002');
});

test('a tag ref reserves a sequence when the draft Release is not visible', () => {
  const result = discoverRelease({
    upstreamRelease: upstreamRelease(),
    existingReleases: [],
    existingTags: [{ name: 'ws1608-one-kvm-0.2.4-v260709-b001' }],
    forceBuild: false,
  });

  assert.equal(result.changed, true);
  assert.equal(result.buildNumber, 2);
  assert.equal(result.buildTag, 'ws1608-one-kvm-0.2.4-v260709-b002');
});

test('the discovery CLI passes tag refs into sequence allocation', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ws1608-discovery-'));
  const releasePath = path.join(directory, 'upstream.json');
  const releasesPath = path.join(directory, 'releases.json');
  const tagsPath = path.join(directory, 'tags.json');
  fs.writeFileSync(releasePath, JSON.stringify(upstreamRelease()));
  fs.writeFileSync(releasesPath, '[]');
  fs.writeFileSync(tagsPath, JSON.stringify([[{
    name: 'ws1608-one-kvm-0.2.4-v260709-b001',
  }]]));

  const result = spawnSync(
    process.execPath,
    ['scripts/discover-release.mjs', releasePath, releasesPath, tagsPath, 'false'],
    { cwd: process.cwd(), encoding: 'utf8' },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^build_number=2$/m);
  assert.match(result.stdout, /^build_tag=ws1608-one-kvm-0\.2\.4-v260709-b002$/m);
});

test('rejects an armhf asset without a GitHub SHA-256 digest', () => {
  assert.throws(
    () => discoverRelease({ upstreamRelease: upstreamRelease(''), existingReleases: [] }),
    /valid sha256 digest/,
  );
});

test('rejects ambiguous armhf assets', () => {
  const release = upstreamRelease();
  release.assets.push({ ...release.assets[1], name: 'one-kvm_0.2.5_armhf.deb' });

  assert.throws(
    () => discoverRelease({ upstreamRelease: release, existingReleases: [] }),
    /exactly one armhf Deb asset/,
  );
});
