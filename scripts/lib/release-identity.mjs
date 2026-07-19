const VERSION_PATTERN = /^[0-9A-Za-z][0-9A-Za-z._+-]*$/;
const TAG_PATTERN = /^[0-9A-Za-z][0-9A-Za-z._-]*$/;
const TIME_PATTERN = /^\d{6}$/;

function assertBuildTime(buildTime) {
  if (!TIME_PATTERN.test(buildTime)) throw new Error('invalid UTC build time');
  const hour = Number(buildTime.slice(0, 2));
  const minute = Number(buildTime.slice(2, 4));
  const second = Number(buildTime.slice(4, 6));
  if (hour > 23 || minute > 59 || second > 59) {
    throw new Error('invalid UTC build time');
  }
}

export function formatReleaseIdentity({ version, upstreamTag, buildTime }) {
  if (typeof version !== 'string' || !VERSION_PATTERN.test(version)) {
    throw new Error('invalid One-KVM version');
  }
  if (typeof upstreamTag !== 'string' || !TAG_PATTERN.test(upstreamTag)) {
    throw new Error('invalid upstream tag');
  }
  assertBuildTime(buildTime);

  const imageStem = [
    `One-KVM_${version}_${upstreamTag}_${buildTime}`,
    'Onecloud_trixie_6.12.28_HDMI-test',
  ].join('_');

  return {
    safeUpstreamTag: upstreamTag,
    buildTag: `ws1608-one-kvm-${version}-${upstreamTag}-${buildTime}`,
    imageStem,
    imageName: `${imageStem}.burn.img`,
  };
}

if (process.argv[1]?.endsWith('release-identity.mjs')) {
  const [, , version, upstreamTag, buildTime] = process.argv;
  console.log(JSON.stringify(formatReleaseIdentity({
    version,
    upstreamTag,
    buildTime,
  })));
}
