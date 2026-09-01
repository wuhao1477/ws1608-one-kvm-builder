#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR=${1:?usage: apply-patches.sh SOURCE_DIR PATCH_DIR}
PATCH_DIR=${2:?usage: apply-patches.sh SOURCE_DIR PATCH_DIR}
[[ -d "$SOURCE_DIR/.git" && ! -L "$SOURCE_DIR" ]] || { echo "invalid git source tree" >&2; exit 1; }
[[ -d "$PATCH_DIR" && ! -L "$PATCH_DIR" ]] || { echo "invalid patch directory" >&2; exit 1; }
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd -P)
PATCH_DIR=$(cd "$PATCH_DIR" && pwd -P)
[[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ]] || { echo "source tree must be clean" >&2; exit 1; }

patches=()
while IFS= read -r patch; do patches+=("$patch"); done \
  < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -print | LC_ALL=C sort)
[[ "${#patches[@]}" -gt 0 ]] || { echo "no patches found" >&2; exit 1; }
for patch in "${patches[@]}"; do
  git -C "$SOURCE_DIR" apply --check "$patch"
  git -C "$SOURCE_DIR" apply "$patch"
  printf 'applied %s\n' "${patch##*/}"
done
