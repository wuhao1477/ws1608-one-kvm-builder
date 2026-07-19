import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

async function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

const [outputPath, imagePath] = process.argv.slice(2);
if (!outputPath || !imagePath) throw new Error('manifest and image paths are required');

const manifest = {
  schema_version: 2,
  board: process.env.BASE_BOARD,
  base: process.env.BASE_ID,
  kernel: process.env.BASE_KERNEL,
  one_kvm_version: process.env.ONE_KVM_VERSION,
  one_kvm_release: process.env.UPSTREAM_TAG,
  package_sha256: process.env.PACKAGE_DIGEST,
  build_tag: process.env.BUILD_TAG,
  build_number: Number(process.env.BUILD_NUMBER),
  builder_commit: process.env.BUILDER_COMMIT,
  image: path.basename(imagePath),
  image_size: fs.statSync(imagePath).size,
  image_sha256: await sha256(imagePath),
};

fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
