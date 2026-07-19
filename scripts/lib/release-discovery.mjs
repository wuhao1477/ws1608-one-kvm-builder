const ARMHF_ASSET = /^one-kvm_(.+)_armhf\.deb$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SAFE_COMPONENT = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const DEFAULT_BASE_FLAVOR = 'Onecloud_trixie_6.12.28_HDMI-test';

function safeComponent(value, label) {
  const component = String(value ?? '');
  if (!SAFE_COMPONENT.test(component)) {
    throw new Error(`${label} is not a safe identity component: ${component}`);
  }
  return component;
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
  const duplicates = new Set();
  for (const line of String(body ?? '').split(/\r?\n/)) {
    const separator = line.indexOf('=');
    const key = separator > 0 ? line.slice(0, separator) : '';
    if (!key) continue;
    if (Object.hasOwn(markers, key)) duplicates.add(key);
    else markers[key] = line.slice(separator + 1);
  }
  for (const key of duplicates) markers[key] = null;
  return markers;
}

function parseBuildRecord(name, prefix, release, published) {
  const marker = `${prefix}-b`;
  if (!name.startsWith(marker)) return null;
  const suffix = name.slice(marker.length);
  if (!/^\d+$/.test(suffix)) return null;
  const buildNumber = Number(suffix);
  if (!Number.isSafeInteger(buildNumber) || buildNumber < 1) return null;
  return {
    release,
    tag: name,
    buildNumber,
    buildRevision: `b${suffix}`,
    markers: parseMarkers(release?.body),
    published,
  };
}

function releaseAssetContract(record, safeVersion, safeReleaseTag, baseFlavor) {
  const imageStem = `${safeVersion}-${safeReleaseTag}-${record.buildRevision}`;
  const imageName = `One-KVM_${imageStem}_${baseFlavor}.burn.img`;
  return [
    [imageName, 'image_name', 'image_sha256'],
    [`${imageName}.xz`, 'compressed_image_name', 'compressed_image_sha256'],
    ['SHA256SUMS', 'checksums_name', 'checksums_sha256'],
    ['manifest.json', 'manifest_name', 'manifest_sha256'],
    ['validation-report.json', 'validation_report_name', 'validation_report_sha256'],
  ];
}

function uploadedAssetMap(release) {
  const assets = Array.isArray(release?.assets) ? release.assets : [];
  if (assets.length !== 5) return null;
  const byName = new Map();
  for (const asset of assets) {
    const name = String(asset?.name ?? '');
    if (!name || byName.has(name) || asset?.state !== 'uploaded') return null;
    let digest;
    try {
      digest = normalizeDigest(asset?.digest);
    } catch {
      return null;
    }
    byName.set(name, digest);
  }
  return byName;
}

function isVerifiedPublishedRecord(record, expected) {
  if (!record.published) return false;
  const markers = record.markers;
  if (
    markers.one_kvm_version !== expected.oneKvmVersion
    || markers.one_kvm_release !== expected.releaseTag
    || markers.package_sha256 !== expected.packageDigest
    || markers.build_tag !== record.tag
    || markers.build_revision !== record.buildRevision
    || markers.build_number !== String(record.buildNumber)
  ) return false;
  const assets = uploadedAssetMap(record.release);
  if (!assets) return false;
  const contract = releaseAssetContract(
    record,
    expected.safeVersion,
    expected.safeReleaseTag,
    expected.baseFlavor,
  );
  return contract.every(([name, nameMarker, digestMarker]) => (
    markers[nameMarker] === name
    && markers[digestMarker] === assets.get(name)
  ));
}

function buildRecords(releases, tags, prefix) {
  const records = [];
  const seen = new Set();
  for (const release of Array.isArray(releases) ? releases : []) {
    const tag = String(release?.tag_name ?? '');
    if (!tag) continue;
    const published = !release?.draft && !release?.prerelease;
    const record = parseBuildRecord(tag, prefix, release, published);
    if (record) {
      records.push(record);
      seen.add(tag);
    }
  }
  for (const tagValue of Array.isArray(tags) ? tags : []) {
    const name = String(tagValue?.name ?? tagValue?.tag_name ?? '');
    if (!name || seen.has(name)) continue;
    const record = parseBuildRecord(name, prefix, {}, false);
    if (record) records.push(record);
  }
  return records;
}

function workflowBuildNumber(runNumberValue, runAttemptValue) {
  const runText = String(runNumberValue ?? '');
  const attemptText = String(runAttemptValue ?? '');
  if (!runText && !attemptText) return null;
  const runNumber = Number(runText);
  const runAttempt = Number(attemptText);
  if (!Number.isSafeInteger(runNumber) || runNumber < 1) {
    throw new Error('workflow run number must be a positive integer');
  }
  if (!Number.isSafeInteger(runAttempt) || runAttempt < 1 || runAttempt > 999) {
    throw new Error('workflow run attempt must be between 1 and 999');
  }
  const buildNumber = runNumber * 1000 + runAttempt;
  if (!Number.isSafeInteger(buildNumber)) throw new Error('workflow build number is too large');
  return buildNumber;
}

export function discoverRelease({
  upstreamRelease,
  existingReleases = [],
  existingTags = [],
  forceBuild = false,
  workflowRunNumber,
  workflowRunAttempt,
  baseFlavor = DEFAULT_BASE_FLAVOR,
}) {
  if (upstreamRelease?.draft || upstreamRelease?.prerelease) {
    throw new Error('latest upstream release must not be draft or prerelease');
  }
  const releaseTag = String(upstreamRelease?.tag_name ?? '');
  if (!releaseTag) throw new Error('upstream release has no tag');

  const asset = selectArmhfAsset(upstreamRelease);
  const safeVersion = safeComponent(asset.oneKvmVersion, 'One-KVM version');
  const safeReleaseTag = safeComponent(releaseTag, 'upstream release tag');
  const safeBaseFlavor = safeComponent(baseFlavor, 'base flavor');
  const prefix = `ws1608-one-kvm-${safeVersion}-${safeReleaseTag}`;
  const records = buildRecords(existingReleases, existingTags, prefix);
  const matching = records
    .filter((record) => isVerifiedPublishedRecord(record, {
      baseFlavor: safeBaseFlavor,
      oneKvmVersion: asset.oneKvmVersion,
      packageDigest: asset.packageDigest,
      releaseTag,
      safeReleaseTag,
      safeVersion,
    }))
    .sort((left, right) => right.buildNumber - left.buildNumber);
  const maxBuildNumber = records.reduce(
    (maximum, record) => Math.max(maximum, record.buildNumber),
    0,
  );
  const changed = Boolean(forceBuild) || matching.length === 0;
  const workflowNumber = workflowBuildNumber(workflowRunNumber, workflowRunAttempt);
  const buildNumber = changed
    ? (workflowNumber ?? maxBuildNumber + 1)
    : matching[0].buildNumber;
  const buildRevision = changed
    ? `b${String(buildNumber).padStart(workflowNumber === null ? 3 : 6, '0')}`
    : matching[0].buildRevision;
  const buildTag = changed ? `${prefix}-${buildRevision}` : matching[0].tag;
  if (changed && records.some((record) => record.tag === buildTag)) {
    throw new Error(`build tag is already reserved: ${buildTag}`);
  }

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
