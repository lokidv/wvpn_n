#!/usr/bin/env bash
# udp2raw_setup.sh – install udp2raw (if missing) and create a systemd service
# Usage:  chmod +x udp2raw_setup.sh && sudo ./udp2raw_setup.sh
# Tested on Ubuntu 20.04/22.04

set -euo pipefail

BIN_DIR="/usr/local/bin/udp2raw"
BIN_FILE="${BIN_DIR}/udp2raw"

green() { printf '\e[32m%s\e[0m\n' "$1"; }
red()   { printf '\e[31m%s\e[0m\n' "$1"; }

###############################################################################
# 1. Install udp2raw if not present
###############################################################################
install_udp2raw() {
  green "→ Installing udp2raw ..."
  apt update
  apt install -y git build-essential golang

  TMP=$(mktemp -d)
  git clone https://github.com/MikeWang000000/udp2raw.git "$TMP/udp2raw"
  pushd "$TMP/udp2raw" >/dev/null
  make
  popd >/dev/null

  mkdir -p "$BIN_DIR"
  cp -r "$TMP/udp2raw"/* "$BIN_DIR/"
  rm -rf "$TMP"
  green "✔ udp2raw installed to $BIN_DIR"
}

[[ -x "$BIN_FILE" ]] || install_udp2raw

###############################################################################
# 2. Collect user inputs (English prompts)
###############################################################################
echo "------------------------------------------------------------"
echo "   udp2raw Service Generator"
echo "------------------------------------------------------------"
echo "1) Foreign server  (mode: server  -s)"
echo "2) Iran server     (mode: client  -c)"
read -rp "Select configuration (1/2): " MODE

read -rp "Service alias (e.g. brave): " SERVICE_ALIAS
# Clean alias: drop leading tcp- or trailing -udp2raw if user typed them
SERVICE_ALIAS=$(echo "$SERVICE_ALIAS" | sed -E 's/^tcp-//' | sed -E 's/-?udp2raw$//')
SERVICE_NAME="tcp-${SERVICE_ALIAS}-udp2raw"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

case "$MODE" in
  1)  # Foreign/server side
    read -rp "Port that foreign server listens on (PORT_LISTEN): " PORT_LISTEN
    read -rp "Local WireGuard port on foreign server (PORT_WIREGUARD): " PORT_WG
    read -rp "Fake domain (e.g. brave.example.com): " FAKE_DOMAIN
    read -rp "Tunnel mode (faketcp/udp/icmp): " TUNNEL_MODE

    EXEC_CMD="${BIN_FILE} -s -l0.0.0.0:${PORT_LISTEN} -r 127.0.0.1:${PORT_WG} \
-k \"Aa@!123456\" --raw-mode ${TUNNEL_MODE} --fake-http ${FAKE_DOMAIN} \
--cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  2)  # Iran/client side
    read -rp "Local port in Iran (IRAN_PORT): " IRAN_PORT
    read -rp "Public IP of foreign server (FOREIGN_IP): " FOREIGN_IP
    read -rp "udp2raw port on foreign server (FOREIGN_PORT): " FOREIGN_PORT
    read -rp "Fake domain (e.g. brave.example.com): " FAKE_DOMAIN
    read -rp "Tunnel mode (faketcp/udp/icmp): " TUNNEL_MODE

    # Ensure prefix “tcp-” appears exactly once
    [[ "${FAKE_DOMAIN}" == tcp-* ]] && FAKE_STR="${FAKE_DOMAIN}" || FAKE_STR="tcp-${FAKE_DOMAIN}"

    EXEC_CMD="${BIN_FILE} -c -l0.0.0.0:${FOREIGN_PORT} -r\"${FOREIGN_IP}\":${IRAN_PORT} \
-k \"Aa@!123456\" --raw-mode ${TUNNEL_MODE} --fake-http ${FAKE_STR} \
--cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  *)
    red "Invalid selection"; exit 1 ;;
esac

###############################################################################
# 3. Create & start systemd unit
###############################################################################
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=udp2raw tunnel (${SERVICE_ALIAS})
After=network.target

[Service]
Type=simple
User=root
ExecStart=${EXEC_CMD}
Restart=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

green "✔ Service ${SERVICE_NAME}.service created and started."
systemctl status "${SERVICE_NAME}.service" --no-pager
