#!/usr/bin/env bash
#
# install_wvpn.sh – Auto-install WireGuard + Node.js + wvpn
# ---------------------------------------------------------
# Usage : chmod +x install_wvpn.sh && sudo ./install_wvpn.sh
# Log   : /var/log/wvpn_install.log

set -euo pipefail
LOG="/var/log/wvpn_install.log"; touch "$LOG"
green(){ echo -e "\e[32m$1\e[0m"; }; red(){ echo -e "\e[31m$1\e[0m"; }
step(){ printf "%s ... " "$1" | tee -a "$LOG"; }; ok(){ green "✅" | tee -a "$LOG"; }
fail(){ red "❌"; exit 1; }

###############################################################################
# 1. Update & base packages
###############################################################################
step "Updating system"; sudo apt update && sudo apt upgrade -y >>"$LOG" 2>&1 && ok || fail
for pkg in nano cron git ca-certificates curl gnupg; do
  step "Installing $pkg"; sudo apt-get install -y "$pkg" >>"$LOG" 2>&1 && ok || fail
done

###############################################################################
# 2. Node.js 20
###############################################################################
step "Adding NodeSource key"; sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
 | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg >>"$LOG" 2>&1 && ok || fail
step "Adding NodeSource repo"
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
 | sudo tee /etc/apt/sources.list.d/nodesource.list >>"$LOG" 2>&1 && ok || fail
step "Installing Node.js"; sudo apt-get update >>"$LOG" 2>&1
sudo apt-get install -y nodejs >>"$LOG" 2>&1 && ok || fail

###############################################################################
# 3. Clone wvpn & deps
###############################################################################
step "Cloning wvpn"; sudo git clone https://github.com/lokidv/wvpn.git /home/wvpn >>"$LOG" 2>&1 && ok || fail
cd /home/wvpn
step "npm install"; sudo npm install >>"$LOG" 2>&1 && ok || fail
step "chmod wireguard-install.sh"; sudo chmod +x /home/wvpn/wireguard-install.sh && ok

###############################################################################
# 4. WireGuard non-interactive install
###############################################################################
step "Installing WireGuard pkgs"; sudo apt-get install -y wireguard iptables resolvconf qrencode >>"$LOG" 2>&1 && ok || fail
step "Generating keys"; SERVER_PRIV_KEY=$(wg genkey); SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY"|wg pubkey); ok

SERVER_PUB_IP=$(ip -4 -o addr show scope global | awk '{print $4}'|cut -d/ -f1|head -1)
SERVER_PUB_NIC=$(ip -4 route ls | awk '/default/{print $5;exit}')
SERVER_WG_NIC="wg0"
SERVER_WG_IPV4="10.66.66.1"
SERVER_PORT=$(shuf -i1500-10000 -n1)        # random port
CLIENT_DNS_1="1.1.1.1"; CLIENT_DNS_2="1.0.0.1"; ALLOWED_IPS="0.0.0.0/0"

sudo mkdir -p /etc/wireguard && sudo chmod 600 -R /etc/wireguard
sudo tee /etc/wireguard/params >/dev/null <<EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}
EOF

step "Creating server config"
sudo tee /etc/wireguard/${SERVER_WG_NIC}.conf >/dev/null <<EOF
[Interface]
Address   = ${SERVER_WG_IPV4}/24
ListenPort= ${SERVER_PORT}
PrivateKey= ${SERVER_PRIV_KEY}
PostUp    = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp    = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp    = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp    = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown  = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown  = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown  = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown  = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
EOF
sudo chmod 600 /etc/wireguard/${SERVER_WG_NIC}.conf && ok

step "Enable ip_forward in 99-sysctl.conf"
sudo sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
grep -q net.ipv4.ip_forward /etc/sysctl.d/99-sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.d/99-sysctl.conf
sudo sysctl --system >>"$LOG" 2>&1 && ok || fail

step "Starting wg-quick@${SERVER_WG_NIC}"
sudo systemctl start wg-quick@${SERVER_WG_NIC} && sudo systemctl enable wg-quick@${SERVER_WG_NIC} >>"$LOG" 2>&1 && ok || fail

###############################################################################
# 5. Create default client “loki” (assume user exists)
###############################################################################
step "Creating default client profile (loki)"
CLIENT_NAME="loki"; CLIENT_WG_IPV4="10.66.66.2"
HOME_DIR="/home/${CLIENT_NAME}"; [ -d "$HOME_DIR" ] || HOME_DIR="/root"
CLIENT_CONF="${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

if [ -f "$CLIENT_CONF" ]; then
  green "Client loki already exists – skipping" | tee -a "$LOG"
else
  CLIENT_PRIV_KEY=$(wg genkey)
  CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
  CLIENT_PSK=$(wg genpsk)
  ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

  sudo tee "$CLIENT_CONF" >/dev/null <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address    = ${CLIENT_WG_IPV4}/32
DNS        = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey    = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint     = ${ENDPOINT}
AllowedIPs   = ${ALLOWED_IPS}
EOF
  sudo chmod 600 "$CLIENT_CONF"

  sudo tee -a /etc/wireguard/${SERVER_WG_NIC}.conf >/dev/null <<EOF

### Client ${CLIENT_NAME}
[Peer]
PublicKey    = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs   = ${CLIENT_WG_IPV4}/32
EOF

  sudo wg syncconf ${SERVER_WG_NIC} <(sudo wg-quick strip ${SERVER_WG_NIC}) >>"$LOG" 2>&1
fi
ok

green "WireGuard ready on port ${SERVER_PORT}"

###############################################################################
# 6. wvpn systemd service
###############################################################################
step "Creating wvpn.service"
sudo tee /etc/systemd/system/wvpn.service >/dev/null <<'UNIT'
[Unit]
Description=Tunnel WireGuard with udp2raw
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/node /home/wvpn/main.js
Restart=no
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now wvpn.service >>"$LOG" 2>&1 && ok || fail

###############################################################################
# 7. cron watchdog for udp2raw
###############################################################################
step "Adding/ensuring cron watchdog"
TMPCRON=$(mktemp)
sudo crontab -l 2>/dev/null >"$TMPCRON" || true
grep -q "udp2raw.service" "$TMPCRON" || echo '* * * * * /bin/systemctl is-active --quiet udp2raw.service || /bin/systemctl restart udp2raw.service' >>"$TMPCRON"
sudo crontab "$TMPCRON"; rm "$TMPCRON"
ok

green "\nSetup finished successfully! Full log: $LOG"
