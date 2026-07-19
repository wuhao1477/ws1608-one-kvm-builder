const FIELD_MAP = [
  ['schema_version', 'schemaVersion'],
  ['board', 'board'],
  ['base', 'base'],
  ['kernel', 'kernel'],
  ['one_kvm_version', 'oneKvmVersion'],
  ['one_kvm_release', 'upstreamTag'],
  ['package_sha256', 'packageDigest'],
  ['build_tag', 'buildTag'],
  ['build_number', 'buildNumber'],
  ['builder_commit', 'builderCommit'],
];
const ALLOWED_KEYS = new Set(FIELD_MAP.map(([key]) => key));

function validateText(value, label) {
  const text = String(value ?? '');
  if (!text || /[\r\n]/.test(text)) throw new Error(`${label} must be one nonempty line`);
  return text;
}

function validateIdentity(values) {
  if (values.schemaVersion !== 1) throw new Error('schema version must be 1');
  if (!Number.isSafeInteger(values.buildNumber) || values.buildNumber < 1) {
    throw new Error('build number must be a positive integer');
  }
  if (!/^[0-9a-f]{64}$/.test(String(values.packageDigest ?? ''))) {
    throw new Error('package digest must be 64 lowercase hexadecimal characters');
  }
  const number = String(values.buildNumber);
  const revisions = [
    `b${number.padStart(3, '0')}`,
    `b${number.padStart(6, '0')}`,
  ];
  if (!revisions.some((revision) => String(values.buildTag ?? '').endsWith(`-${revision}`))) {
    throw new Error(`build tag must end with one of ${revisions.join(', ')}`);
  }
}

export function createImageMetadata(values) {
  validateIdentity(values);
  const lines = FIELD_MAP.map(([key, property]) => {
    const value = validateText(values[property], property);
    return `${key}=${value}`;
  });
  return `${lines.join('\n')}\n`;
}

export function parseImageMetadata(text) {
  const result = {};
  for (const line of String(text).split(/\r?\n/).filter(Boolean)) {
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error(`invalid metadata line: ${line}`);
    const key = line.slice(0, separator);
    if (!ALLOWED_KEYS.has(key)) throw new Error(`unknown key: ${key}`);
    if (Object.hasOwn(result, key)) throw new Error(`duplicate key: ${key}`);
    result[key] = line.slice(separator + 1);
  }
  for (const key of ALLOWED_KEYS) {
    if (!Object.hasOwn(result, key)) throw new Error(`missing key: ${key}`);
  }
  return result;
}

export function assertImageMetadata(text, expected) {
  const actual = parseImageMetadata(text);
  const canonical = parseImageMetadata(createImageMetadata(expected));
  for (const [key, value] of Object.entries(canonical)) {
    if (actual[key] !== value) {
      throw new Error(`${key} mismatch: expected ${value}, found ${actual[key]}`);
    }
  }
  return actual;
}
