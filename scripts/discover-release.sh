#!/usr/bin/env bash
set -Eeuo pipefail

UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-mofeng-git/One-KVM}
TARGET_REPOSITORY=${GITHUB_REPOSITORY:-}
FORCE_BUILD=${FORCE_BUILD:-false}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/null}

for command in gh jq; do
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
safe_tag=$(tr -c 'A-Za-z0-9._-' '-' <<<"$release_tag" | sed 's/-$//')
build_tag="ws1608-one-kvm-$safe_tag"
changed=true

if [[ -n "$TARGET_REPOSITORY" ]] && gh api "repos/$TARGET_REPOSITORY/releases/tags/$build_tag" >/dev/null 2>&1; then
  changed=false
fi
if [[ "$FORCE_BUILD" == true ]]; then changed=true; fi

{
  echo "changed=$changed"
  echo "release_tag=$release_tag"
  echo "build_tag=$build_tag"
  echo "one_kvm_version=$one_kvm_version"
  echo "package_name=$package_name"
  echo "package_url=$package_url"
  echo "package_digest=$package_digest"
} >> "$OUTPUT_FILE"

echo "One-KVM $one_kvm_version ($release_tag): changed=$changed"
