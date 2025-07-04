#!/usr/bin/env bash
# udp2raw_setup.sh – install udp2raw (if missing) and create a systemd service
#   chmod +x udp2raw_setup.sh && sudo ./udp2raw_setup.sh

set -euo pipefail

BIN_DIR="/usr/local/bin/udp2raw"
BIN_FILE="${BIN_DIR}/udp2raw"

green(){ printf '\e[32m%s\e[0m\n' "$1"; }
red()  { printf '\e[31m%s\e[0m\n' "$1"; }

###############################################################################
# 1. Install udp2raw (only once)
###############################################################################
install_udp2raw() {
  green "→ Installing udp2raw ..."
  apt update
  apt install -y git build-essential golang

  TMP=$(mktemp -d)
  git clone https://github.com/MikeWang000000/udp2raw.git "$TMP/udp2raw"
  make -C "$TMP/udp2raw"
  mkdir -p "$BIN_DIR"
  cp -r "$TMP/udp2raw"/* "$BIN_DIR/"
  rm -rf "$TMP"
  green "✔ udp2raw installed to $BIN_DIR"
}
[[ -x "$BIN_FILE" ]] || install_udp2raw

###############################################################################
# 2. Interactive prompts (English)
###############################################################################
echo "------------------------------------------------------------"
echo "  udp2raw Service Generator"
echo "------------------------------------------------------------"
echo "1) Foreign server  (mode: -s)"
echo "2) Iran server     (mode: -c)"
read -rp "Select configuration (1/2): " MODE

read -rp "Service alias (e.g. brave): " RAW_ALIAS
# Strip ANY leading tcp- or udp2raw- and any trailing -udp2raw
SERVICE_ALIAS=$(echo "$RAW_ALIAS" | \
                sed -E 's/^(tcp-)?(udp2raw-)?//' | \
                sed -E 's/-?udp2raw$//')
SERVICE_NAME="tcp-${SERVICE_ALIAS}-udp2raw"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

case "$MODE" in
  1)  # Foreign/server side
    read -rp "Listening port on foreign server (PORT_LISTEN): " PORT_LISTEN
    read -rp "Local WireGuard port (PORT_WG): " PORT_WG
    read -rp "Fake domain (e.g. brave.example.com): " FAKE_DOMAIN
    read -rp "Tunnel mode (faketcp/udp/icmp): " TUNNEL_MODE

    EXEC_CMD="${BIN_FILE} -s -l0.0.0.0:${PORT_LISTEN} \
-r127.0.0.1:${PORT_WG} -k \"Aa@!123456\" \
--raw-mode ${TUNNEL_MODE} --fake-http ${FAKE_DOMAIN} \
--cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  2)  # Iran/client side
    read -rp "Local port in Iran (IRAN_PORT): " IRAN_PORT
    read -rp "Foreign server IP (FOREIGN_IP): " FOREIGN_IP
    read -rp "udp2raw port on foreign server (FOREIGN_PORT): " FOREIGN_PORT
    read -rp "Fake domain (e.g. brave.example.com): " FAKE_DOMAIN
    read -rp "Tunnel mode (faketcp/udp/icmp): " TUNNEL_MODE

    [[ $FAKE_DOMAIN == tcp-* ]] && FAKE_DOM=$FAKE_DOMAIN || FAKE_DOM="tcp-${FAKE_DOMAIN}"
    EXEC_CMD="${BIN_FILE} -c -l0.0.0.0:${IRAN_PORT} \
-r\"${FOREIGN_IP}\":${FOREIGN_PORT} -k \"Aa@!123456\" \
--raw-mode ${TUNNEL_MODE} --fake-http ${FAKE_DOM} \
--cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  *)  red "Invalid selection"; exit 1 ;;
esac

###############################################################################
# 3. Create & start systemd unit
###############################################################################
cat > "$SERVICE_FILE" <<EOF
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
