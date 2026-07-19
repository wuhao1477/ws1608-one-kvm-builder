import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

async function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

function writeAtomic(filePath, text) {
  try {
    if (fs.lstatSync(filePath).isSymbolicLink()) throw new Error(`refusing symlink: ${filePath}`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const temporary = `${filePath}.tmp-${process.pid}-${crypto.randomUUID()}`;
  try {
    fs.writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx' });
    fs.renameSync(temporary, filePath);
  } finally {
    try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

const [outputPath, imagePath] = process.argv.slice(2);
if (!outputPath || !imagePath) throw new Error('manifest and image paths are required');

function env(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const imageStat = fs.lstatSync(imagePath);
if (!imageStat.isFile()) throw new Error('image must be a regular file');

const manifest = {
  schema_version: 2,
  board: env('BASE_BOARD'),
  base: env('BASE_ID'),
  kernel: env('BASE_KERNEL'),
  one_kvm_version: env('ONE_KVM_VERSION'),
  one_kvm_release: env('UPSTREAM_TAG'),
  package_name: env('PACKAGE_NAME'),
  package_url: env('PACKAGE_URL'),
  package_sha256: env('PACKAGE_DIGEST'),
  base_release_tag: env('BASE_RELEASE_TAG'),
  base_image_name: env('BASE_IMAGE_NAME'),
  base_image_url: env('BASE_IMAGE_URL'),
  base_sha256: env('BASE_IMAGE_SHA256'),
  build_tag: env('BUILD_TAG'),
  build_revision: env('BUILD_REVISION'),
  build_number: Number(env('BUILD_NUMBER')),
  builder_commit: env('BUILDER_COMMIT'),
  github_run_id: env('GITHUB_RUN_ID'),
  github_run_attempt: env('GITHUB_RUN_ATTEMPT'),
  github_run_number: env('GITHUB_RUN_NUMBER'),
  amlimg_repository: env('AMLIMG_REPOSITORY'),
  amlimg_commit: env('AMLIMG_COMMIT'),
  image: path.basename(imagePath),
  image_size: imageStat.size,
  image_sha256: await sha256(imagePath),
};

writeAtomic(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
