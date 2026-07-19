#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-mofeng-git/One-KVM}
TARGET_REPOSITORY=${GITHUB_REPOSITORY:-}
FORCE_BUILD=${FORCE_BUILD:-false}
BUILD_TIME_UTC=${BUILD_TIME_UTC:-$(date -u +%H%M%S)}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/null}

for command in gh jq node; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

release=$(gh api "repos/$UPSTREAM_REPOSITORY/releases/latest")
release_tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$release")
asset_count=$(jq '[.assets[] | select(.name | startswith("one-kvm_") and endswith("_armhf.deb"))] | length' <<<"$release")
[[ "$asset_count" -eq 1 ]] || {
  echo "expected one armhf Deb asset, found $asset_count" >&2
  exit 1
}

asset=$(jq -c '.assets[] | select(.name | startswith("one-kvm_") and endswith("_armhf.deb"))' <<<"$release")
package_name=$(jq -r '.name' <<<"$asset")
package_url=$(jq -r '.browser_download_url' <<<"$asset")
package_digest=$(jq -r '.digest // empty | sub("^sha256:"; "")' <<<"$asset")
one_kvm_version=${package_name#one-kvm_}
one_kvm_version=${one_kvm_version%_armhf.deb}

identity_json=$(node "$ROOT_DIR/scripts/lib/release-identity.mjs"   "$one_kvm_version" "$release_tag" "$BUILD_TIME_UTC")
safe_upstream_tag=$(jq -er '.safeUpstreamTag' <<<"$identity_json")
build_tag=$(jq -er '.buildTag' <<<"$identity_json")
image_stem=$(jq -er '.imageStem' <<<"$identity_json")
image_name=$(jq -er '.imageName' <<<"$identity_json")
changed=true
existing_build_tag=

if [[ -n "$TARGET_REPOSITORY" ]]; then
  published_releases=$(gh api --paginate --slurp     "repos/$TARGET_REPOSITORY/releases?per_page=100" | jq 'add')
  existing_build_tag=$(jq -r     --arg legacy "ws1608-one-kvm-$safe_upstream_tag"     --arg prefix "ws1608-one-kvm-$one_kvm_version-$safe_upstream_tag-" '
      def has_required_assets:
        [.assets[]? | select(.state == "uploaded") | .name] as $names
        | ($names | index("SHA256SUMS") != null)
        and ($names | index("manifest.json") != null)
        and ([$names[] | select(endswith(".burn.img"))] | length == 1)
        and ([$names[] | select(endswith(".burn.img.xz"))] | length == 1);
      first(.[] | select(
        .draft == false
        and .prerelease == false
        and (.tag_name == $legacy
          or ((.tag_name | startswith($prefix))
            and (.tag_name | test("[0-9]{6}$"))))
        and has_required_assets
      ) | .tag_name) // empty
    ' <<<"$published_releases")
  if [[ -n "$existing_build_tag" ]]; then changed=false; fi
fi

if [[ "$FORCE_BUILD" == true ]]; then changed=true; fi

{
  echo "changed=$changed"
  echo "release_tag=$release_tag"
  echo "build_tag=$build_tag"
  echo "build_stamp=$BUILD_TIME_UTC"
  echo "image_stem=$image_stem"
  echo "image_name=$image_name"
  echo "one_kvm_version=$one_kvm_version"
  echo "package_name=$package_name"
  echo "package_url=$package_url"
  echo "package_digest=$package_digest"
  echo "existing_build_tag=$existing_build_tag"
} >> "$OUTPUT_FILE"

echo "One-KVM $one_kvm_version ($release_tag): changed=$changed build_tag=$build_tag existing=$existing_build_tag"
