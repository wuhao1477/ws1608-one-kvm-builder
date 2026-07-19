import fs from 'node:fs';

import { discoverRelease } from './lib/release-discovery.mjs';

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8'));
}

function readPages(path) {
  const payload = readJson(path);
  if (!Array.isArray(payload)) return payload;
  return payload.flatMap((page) => (Array.isArray(page) ? page : [page]));
}

const [releasePath, releasesPath, forceValue] = process.argv.slice(2);
if (!releasePath || !releasesPath) throw new Error('release JSON paths are required');

const result = discoverRelease({
  upstreamRelease: readJson(releasePath),
  existingReleases: readPages(releasesPath),
  forceBuild: forceValue === 'true',
});

for (const [key, value] of Object.entries({
  changed: String(result.changed),
  release_tag: result.releaseTag,
  build_tag: result.buildTag,
  build_number: String(result.buildNumber),
  build_revision: result.buildRevision,
  image_stem: result.imageStem,
  one_kvm_version: result.oneKvmVersion,
  package_name: result.packageName,
  package_url: result.packageUrl,
  package_digest: result.packageDigest,
})) {
  process.stdout.write(`${key}=${value}\n`);
}
process.stderr.write(
  `One-KVM ${result.oneKvmVersion} (${result.releaseTag}) ${result.buildTag}: changed=${result.changed}\n`,
);
