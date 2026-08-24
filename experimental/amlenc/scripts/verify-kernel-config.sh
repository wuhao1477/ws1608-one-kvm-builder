#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:?usage: verify-kernel-config.sh SOURCE_DIR CONFIG_FILE}
CONFIG_FILE=${2:?usage: verify-kernel-config.sh SOURCE_DIR CONFIG_FILE}
CONFIG_TOOL="$SOURCE_DIR/scripts/config"

for option in CMA AMLOGIC_ION USB_GADGET AM_ENCODER; do
  state=$("$CONFIG_TOOL" --file "$CONFIG_FILE" --state "$option")
  [[ "$state" == y ]] || {
    echo "required kernel option CONFIG_$option is $state" >&2
    exit 1
  }
done

grep -Fqx 'CONFIG_CMA_SIZE_MBYTES=64' "$CONFIG_FILE" || {
  echo 'CONFIG_CMA_SIZE_MBYTES must be 64' >&2
  exit 1
}

for option in MALI400 MALI450 MALI400_UMP FB_AMLOGIC_UMP FB_TFT UMP; do
  state=$("$CONFIG_TOOL" --file "$CONFIG_FILE" --state "$option")
  [[ "$state" == n || "$state" == undef ]] || {
    echo "unwanted kernel option CONFIG_$option is $state" >&2
    exit 1
  }
done
