#!/usr/bin/env bash
# udp2raw_setup.sh  –  Install & configure udp2raw + systemd service
# Run as root:  chmod +x udp2raw_setup.sh && sudo ./udp2raw_setup.sh

set -euo pipefail

BIN_DIR="/usr/local/bin/udp2raw"
BIN_FILE="${BIN_DIR}/udp2raw"
SERVICE_FILE="/etc/systemd/system/tcp-udp2raw.service"

green(){ echo -e "\e[32m$1\e[0m"; }
red(){ echo -e "\e[31m$1\e[0m"; }

install_udp2raw() {
  green "→ Installing udp2raw ..."
  apt update
  apt install -y git build-essential golang

  TMP_DIR=$(mktemp -d)
  git clone https://github.com/MikeWang000000/udp2raw.git "$TMP_DIR/udp2raw"
  pushd "$TMP_DIR/udp2raw" >/dev/null
  make
  popd >/dev/null

  mkdir -p "$BIN_DIR"
  cp -r "$TMP_DIR/udp2raw"/* "$BIN_DIR/"
  rm -rf "$TMP_DIR"
  green "✅ udp2raw installed to $BIN_DIR"
}

[[ -x "$BIN_FILE" ]] || install_udp2raw

echo
echo "------------------------------------------------------------"
echo "  udp2raw Service Generator"
echo "------------------------------------------------------------"
echo "1) سرور خارج (mode: server -s)"
echo "2) سرور ایران  (mode: client -c)"
read -rp "کدام را می‌خواهید پیکربندی کنید؟ (1/2) " MODE

case "$MODE" in
  1)
    read -rp "پورت سمت ایران (PORTIRAN): " PORT_IR
    read -rp "پورت WireGuard در سرور (PORTWIRE): " PORT_WIRE
    read -rp "دامنهٔ فیک (مثال: zar.tonmeme.app): " FAKE_DOMAIN
    read -rp "حالت تونل (faketcp|udp|icmp): " TUNNEL_MODE

    EXEC_CMD="${BIN_FILE} -s -l0.0.0.0:${PORT_IR} -r 127.0.0.1:${PORT_WIRE} -k \"Aa@!123456\" --raw-mode ${TUNNEL_MODE} --fake-http ${FAKE_DOMAIN} --cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  2)
    read -rp "پورت لوکال در ایران (IRANPORT): " PORT_IR
    read -rp "IP سرور خارج (KHAREJIP): " KHAREJ_IP
    read -rp "پورت udp2raw سرور خارج (KHAREJPORT): " KHAREJ_PORT
    read -rp "دامنهٔ فیک (مثال: zar.tonmeme.app): " FAKE_DOMAIN
    read -rp "حالت تونل (faketcp|udp|icmp): " TUNNEL_MODE

    EXEC_CMD="${BIN_FILE} -c -l0.0.0.0:${PORT_IR} -r\"${KHAREJ_IP}\":${KHAREJ_PORT} -k \"Aa@!123456\" --raw-mode ${TUNNEL_MODE} --fake-http tcp-${FAKE_DOMAIN} --cipher-mode aes128cbc --auth-mode hmac_sha1 --seq-mode 2"
    ;;
  *)
    red "گزینهٔ نامعتبر!"; exit 1 ;;
esac

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tunnel WireGuard with udp2raw
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
systemctl enable --now tcp-udp2raw.service

green "✅ سرویس tcp-udp2raw.service ساخته و اجرا شد!"
systemctl status tcp-udp2raw.service --no-pager
