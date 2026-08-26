#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
PACKAGE_DIR=${1:?package directory is required}
# shellcheck disable=SC1091
source "$ROOT_DIR/experimental/amlenc/config/login.env"

fail() { echo "login postinst configuration failed: $*" >&2; exit 1; }
[[ -d "$PACKAGE_DIR" && ! -L "$PACKAGE_DIR" ]] || fail 'package directory is unsafe'
[[ -d "$PACKAGE_DIR/DEBIAN" && ! -L "$PACKAGE_DIR/DEBIAN" ]] || fail 'DEBIAN directory is missing'

postinst="$PACKAGE_DIR/DEBIAN/postinst"
if [[ -e "$postinst" && ! -f "$postinst" ]]; then fail 'postinst is not a regular file'; fi
if [[ ! -e "$postinst" ]]; then printf '#!/bin/sh\nset -e\n' >"$postinst"; fi
if grep -Fqx '# ws1608-amlenc-login' "$postinst"; then exit 0; fi

snippet=$(mktemp)
cleanup() { rm -f "$snippet" "$postinst.tmp"; }
trap cleanup EXIT
cat >"$snippet" <<EOF
# ws1608-amlenc-login
DEFAULT_LOGIN_USER='$DEFAULT_LOGIN_USER'
DEFAULT_LOGIN_PASSWORD='$DEFAULT_LOGIN_PASSWORD'
printf '%s:%s\\n' "\$DEFAULT_LOGIN_USER" "\$DEFAULT_LOGIN_PASSWORD" | chpasswd
passwd -u "\$DEFAULT_LOGIN_USER"
install -d -m 0755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/ws1608-amlenc.conf <<'SSH_EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
PermitRootLogin yes
SSH_EOF
chmod 0644 /etc/ssh/sshd_config.d/ws1608-amlenc.conf
if [ -f /lib/systemd/system/ssh.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sfn /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service
elif [ -x /etc/init.d/ssh ] && command -v update-rc.d >/dev/null 2>&1; then
  update-rc.d ssh defaults
fi
EOF
awk -v snippet="$snippet" '
  { lines[NR] = $0 }
  END {
    last_exit = 0
    for (line_no = 1; line_no <= NR; line_no++) if (lines[line_no] == "exit 0") last_exit = line_no
    for (line_no = 1; line_no <= NR; line_no++) {
      if (line_no == last_exit) while ((getline line < snippet) > 0) print line
      print lines[line_no]
    }
    if (last_exit == 0) while ((getline line < snippet) > 0) print line
    close(snippet)
  }
' "$postinst" >"$postinst.tmp"
mv "$postinst.tmp" "$postinst"
chmod 0755 "$postinst"
