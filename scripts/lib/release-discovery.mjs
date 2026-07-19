const ARMHF_ASSET = /^one-kvm_(.+)_armhf\.deb$/;
const SHA256 = /^[0-9a-f]{64}$/;

function safeComponent(value, label) {
  const safe = String(value ?? '')
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!safe) throw new Error(`${label} is empty after sanitization`);
  return safe;
}

function normalizeDigest(value) {
  const digest = String(value ?? '').replace(/^sha256:/i, '').toLowerCase();
  if (!SHA256.test(digest)) throw new Error('armhf asset has no valid sha256 digest');
  return digest;
}

function selectArmhfAsset(release) {
  const assets = Array.isArray(release?.assets) ? release.assets : [];
  const matches = assets.filter((asset) => ARMHF_ASSET.test(String(asset?.name ?? '')));
  if (matches.length !== 1) {
    throw new Error(`expected exactly one armhf Deb asset, found ${matches.length}`);
  }
  const match = ARMHF_ASSET.exec(matches[0].name);
  const packageUrl = String(matches[0].browser_download_url ?? '');
  if (!packageUrl.startsWith('https://')) throw new Error('armhf asset has no HTTPS download URL');
  return {
    packageName: matches[0].name,
    packageUrl,
    oneKvmVersion: match[1],
    packageDigest: normalizeDigest(matches[0].digest),
  };
}

function parseMarkers(body) {
  const markers = {};
  for (const line of String(body ?? '').split(/\r?\n/)) {
    const separator = line.indexOf('=');
    if (separator > 0) markers[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return markers;
}

function buildRecords(releases, prefix) {
  return (Array.isArray(releases) ? releases : [])
    .map((release) => {
      const tag = String(release?.tag_name ?? '');
      const marker = `${prefix}-b`;
      if (!tag.startsWith(marker)) return null;
      const suffix = tag.slice(marker.length);
      if (!/^\d+$/.test(suffix)) return null;
      return {
        release,
        tag,
        buildNumber: Number(suffix),
        markers: parseMarkers(release.body),
        published: !release?.draft && !release?.prerelease,
      };
    })
    .filter(Boolean);
}

export function discoverRelease({ upstreamRelease, existingReleases = [], forceBuild = false }) {
  if (upstreamRelease?.draft || upstreamRelease?.prerelease) {
    throw new Error('latest upstream release must not be draft or prerelease');
  }
  const releaseTag = String(upstreamRelease?.tag_name ?? '');
  if (!releaseTag) throw new Error('upstream release has no tag');

  const asset = selectArmhfAsset(upstreamRelease);
  const safeVersion = safeComponent(asset.oneKvmVersion, 'One-KVM version');
  const safeReleaseTag = safeComponent(releaseTag, 'upstream release tag');
  const prefix = `ws1608-one-kvm-${safeVersion}-${safeReleaseTag}`;
  const records = buildRecords(existingReleases, prefix);
  const matching = records
    .filter((record) => record.published)
    .filter((record) => record.markers.one_kvm_release === releaseTag)
    .filter((record) => record.markers.package_sha256 === asset.packageDigest)
    .sort((left, right) => right.buildNumber - left.buildNumber);
  const maxBuildNumber = records.reduce(
    (maximum, record) => Math.max(maximum, record.buildNumber),
    0,
  );
  const changed = Boolean(forceBuild) || matching.length === 0;
  const buildNumber = changed ? maxBuildNumber + 1 : matching[0].buildNumber;
  const buildRevision = `b${String(buildNumber).padStart(3, '0')}`;
  const buildTag = `${prefix}-${buildRevision}`;

  return {
    changed,
    releaseTag,
    safeReleaseTag,
    packageName: asset.packageName,
    packageUrl: asset.packageUrl,
    packageDigest: asset.packageDigest,
    oneKvmVersion: asset.oneKvmVersion,
    safeVersion,
    buildNumber,
    buildRevision,
    buildTag,
    imageStem: `${safeVersion}-${safeReleaseTag}-${buildRevision}`,
  };
}
