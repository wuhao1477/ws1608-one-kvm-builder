#!/bin/bash
# 一键安装 One-KVM 可选扩展到 One-KVM 固定查找的 /usr/bin 路径（ttyd 已内置在镜像里）。
#   ~/one-kvm-extensions.sh              安装全部未安装的扩展
#   ~/one-kvm-extensions.sh frpc gostc   只安装（或重装）指定扩展
# 访问 GitHub 慢时可加代理前缀：GHPROXY_PREFIX=https://ghfast.top/ ~/one-kvm-extensions.sh
# 下载内容一律按固定 sha256 校验；gostc/easytier 与上游 One-KVM Docker 镜像使用的版本一致。
set -Eeuo pipefail

NAMES=(frpc easytier gostc)

# 输出：安装路径 下载地址 sha256 包内文件
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

missing() {
  local name path
  for name in "${NAMES[@]}"; do
    read -r path _ <<<"$(spec "$name")"
    [[ -x $path ]] || echo "$name"
  done
}

if [[ ${1:-} == --hint ]]; then
  todo=$(missing)
  [[ -z $todo ]] || printf '\nOne-KVM 可选扩展未安装：%s\n运行 ~/one-kvm-extensions.sh 一键安装，或只装其中一个，如 ~/one-kvm-extensions.sh frpc\n\n' "${todo//$'\n'/ }"
  exit 0
fi

[[ $(id -u) == 0 ]] || { echo '请用 root 运行' >&2; exit 1; }
if (($#)); then targets=("$@"); else mapfile -t targets < <(missing); fi
((${#targets[@]})) || { echo '所有扩展均已安装'; exit 0; }
for name in "${targets[@]}"; do spec "$name" >/dev/null; done

need() { command -v "$1" >/dev/null || { apt-get update && apt-get install -y --no-install-recommends "$@"; }; }
need curl ca-certificates
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for name in "${targets[@]}"; do
  read -r path url sha member <<<"$(spec "$name")"
  echo "下载 $name：$url"
  curl -fL --retry 3 -o "$work/pkg" "${GHPROXY_PREFIX:-}$url"
  echo "$sha  $work/pkg" | sha256sum --check
  if [[ $url == *.zip ]]; then need unzip; unzip -p "$work/pkg" "$member" >"$work/bin"; else tar -xzOf "$work/pkg" "$member" >"$work/bin"; fi
  install -m 0755 "$work/bin" "$path"
  echo "已安装 $name -> $path"
done

# One-KVM 只在启动时检测扩展是否存在，必须重启才能在网页里启用。
echo '正在重启 one-kvm 使新扩展生效；在 ttyd 网页终端里运行时连接会断开，刷新页面即可。'
systemctl --no-block restart one-kvm
