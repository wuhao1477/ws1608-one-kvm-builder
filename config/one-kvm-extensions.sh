#!/bin/bash
# 一键安装 One-KVM 可选扩展到 One-KVM 固定查找的 /usr/bin 路径（ttyd 已内置在镜像里）。
#   ~/one-kvm-extensions.sh              交互选择扩展和下载源
#   ~/one-kvm-extensions.sh frpc gostc   只安装（或重装）指定扩展
# 非交互调用可通过 MIRROR_PREFIX 或兼容的 GHPROXY_PREFIX 指定镜像前缀。
# 下载内容一律按固定 sha256 校验；gostc/easytier 与上游 One-KVM Docker 镜像使用的版本一致。
set -Eeuo pipefail

NAMES=(frpc easytier gostc)
ONE_KVM_EXTENSIONS_ROOT=${ONE_KVM_EXTENSIONS_ROOT:-}
MIRROR_PREFIX=${MIRROR_PREFIX:-${GHPROXY_PREFIX:-}}

root_path() { printf '%s%s' "$ONE_KVM_EXTENSIONS_ROOT" "$1"; }

# 输出：安装路径 下载地址 压缩包 sha256 包内文件
spec() {
  case $1 in
    frpc) echo /usr/bin/frpc \
      https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_arm.tar.gz \
      f40a984f83e8d34a9241b0be4a9d5fbcfe513a4a5c022b84a02637ff6d36833b frp_0.71.0_linux_arm/frpc ;;
    easytier) echo /usr/bin/easytier-core \
      https://github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-linux-armv7hf-v2.4.5.zip \
      be579b9e54c319e0b0cf9ab615b684d50c9f9c8e8617d28abdaa41cebf9a8711 easytier-linux-armv7hf/easytier-core ;;
    gostc) echo /usr/bin/gostc \
      https://github.com/SianHH/gostc-open/releases/download/v2.0.9/gostc_linux_arm_7.tar.gz \
      abca04c0503245ad5238d4482111b4a0ca2959daf460cd2abba47f3fce292a6b gostc ;;
    *) echo "未知扩展：$1（可选：${NAMES[*]}）" >&2; return 1 ;;
  esac
}

binary_sha() {
  case $1 in
    frpc) echo d92fcc4e62232bae6d58030d2a73f3d2caf49e19742800c9a861a621c2ad1d1a ;;
    easytier) echo 0308f2f32d885ed8414a220120a61dac717be2d666ba7314fee0bdd7a6dbdc90 ;;
    gostc) echo 25f9ac9c5183e5f03516132fd6bbed954744babc555d38d8552aff82b3cf8eea ;;
    *) return 1 ;;
  esac
}

missing() {
  local name path
  for name in "${NAMES[@]}"; do
    read -r path _ <<<"$(spec "$name")"
    path=$(root_path "$path")
    [[ -x $path ]] || echo "$name"
  done
}

interactive_enabled() {
  [[ ${ONE_KVM_EXTENSIONS_INTERACTIVE:-} == 1 || ( -t 0 && -t 1 ) ]]
}

select_targets() {
  local choice item index name path status
  printf '\n选择要安装的扩展（可输入多个编号，如 1,3）：\n'
  for index in "${!NAMES[@]}"; do
    name=${NAMES[index]}
    read -r path _ <<<"$(spec "$name")"
    path=$(root_path "$path")
    status=未安装
    [[ -x $path ]] && status=已安装
    printf '  %s) %s（%s）\n' "$((index + 1))" "$name" "$status"
  done
  printf '  4) 全部未安装\n  0) 取消\n选择：'
  read -r choice || return 1
  choice=${choice//[[:space:]]/}
  [[ $choice == 0 ]] && { echo '已取消安装'; exit 0; }
  [[ $choice == 4 ]] && { mapfile -t targets < <(missing); return; }
  [[ -n $choice ]] || { echo '选择无效' >&2; return 1; }
  IFS=',' read -r -a choices <<<"$choice"
  for item in "${choices[@]}"; do
    [[ $item =~ ^[1-3]$ ]] || { echo "选择无效：$item" >&2; return 1; }
    targets+=("${NAMES[$((item - 1))]}")
  done
}

select_mirror() {
  local choice custom
  printf '\n选择下载源：\n'
  printf '  1) GitHub 直连\n  2) GitHub 镜像（ghfast.top）\n'
  printf '  3) GitHub 镜像（ghproxy.net）\n  4) 自定义镜像前缀\n  0) 取消\n选择：'
  read -r choice || return 1
  case $choice in
    0) echo '已取消安装'; exit 0 ;;
    1) MIRROR_PREFIX= ;;
    2) MIRROR_PREFIX=https://ghfast.top/ ;;
    3) MIRROR_PREFIX=https://ghproxy.net/ ;;
    4)
      printf '请输入镜像前缀（例如 https://ghfast.top）：'
      read -r custom || return 1
      [[ -n $custom ]] || { echo '镜像前缀不能为空' >&2; return 1; }
      MIRROR_PREFIX=$custom
      ;;
    *) echo "选择无效：$choice" >&2; return 1 ;;
  esac
  [[ -n $MIRROR_PREFIX ]] && MIRROR_PREFIX=${MIRROR_PREFIX%/}/
}

[[ -n $MIRROR_PREFIX ]] && MIRROR_PREFIX=${MIRROR_PREFIX%/}/

if [[ ${1:-} == --hint ]]; then
  todo=$(missing)
  [[ -z $todo ]] || printf '\nOne-KVM 可选扩展未安装：%s\n运行 ~/one-kvm-extensions.sh 一键安装，或只装其中一个，如 ~/one-kvm-extensions.sh frpc\n\n' "${todo//$'\n'/ }"
  exit 0
fi
if [[ ${1:-} == --verify-root ]]; then
  [[ $# -ge 2 ]] || { echo '--verify-root 需要 rootfs 路径' >&2; exit 1; }
  ONE_KVM_EXTENSIONS_ROOT=$2
  shift 2
  for name in "$@"; do
    read -r path _ <<<"$(spec "$name")"
    binary_digest=$(binary_sha "$name")
    path=$(root_path "$path")
    [[ -x $path ]] || { echo "扩展未预装：$name" >&2; exit 1; }
    echo "$binary_digest  $path" | sha256sum --check --quiet
  done
  exit 0
fi

targets=()
if (($#)); then
  targets=("$@")
elif interactive_enabled; then
  select_targets
  ((${#targets[@]})) || { echo '所有扩展均已安装'; exit 0; }
  select_mirror
else
  mapfile -t targets < <(missing)
fi
((${#targets[@]})) || { echo '所有扩展均已安装'; exit 0; }
[[ $(id -u) == 0 ]] || { echo '请用 root 运行' >&2; exit 1; }
for name in "${targets[@]}"; do spec "$name" >/dev/null; done

need() { command -v "$1" >/dev/null || { apt-get update && apt-get install -y --no-install-recommends "$@"; }; }
need curl ca-certificates
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for name in "${targets[@]}"; do
  read -r path url sha member <<<"$(spec "$name")"
  binary_digest=$(binary_sha "$name")
  path=$(root_path "$path")
  download_url="${MIRROR_PREFIX}${url}"
  echo "下载 ${name}：$download_url"
  curl -fL --retry 3 -o "$work/pkg" "$download_url"
  echo "$sha  $work/pkg" | sha256sum --check
  if [[ $url == *.zip ]]; then need unzip; unzip -p "$work/pkg" "$member" >"$work/bin"; else tar -xzOf "$work/pkg" "$member" >"$work/bin"; fi
  echo "$binary_digest  $work/bin" | sha256sum --check
  install -m 0755 "$work/bin" "$path"
  echo "已安装 ${name} -> $path"
done

[[ -n "$ONE_KVM_EXTENSIONS_ROOT" ]] && exit 0

# One-KVM 只在启动时检测扩展是否存在，必须重启才能在网页里启用。
echo '正在重启 one-kvm 使新扩展生效；在 ttyd 网页终端里运行时连接会断开，刷新页面即可。'
systemctl --no-block restart one-kvm
