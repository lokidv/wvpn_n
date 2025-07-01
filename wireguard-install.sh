#!/bin/bash

# Secure WireGuard server installer (IPv4-only)
# Based on https://github.com/angristan/wireguard-install
# Modified to strip all IPv6 logic.

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "You need to run this script as root"
		exit 1
	fi
}

function checkVirt() {
	if [ "$(systemd-detect-virt)" == "openvz" ]; then
		echo "OpenVZ is not supported"
		exit 1
	fi
	if [ "$(systemd-detect-virt)" == "lxc" ]; then
		echo "LXC is not supported (yet)."
		exit 1
	fi
}

function checkOS() {
	source /etc/os-release
	OS="${ID}"
	if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
		if [[ ${VERSION_ID} -lt 10 ]]; then
			echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
			exit 1
		fi
		OS=debian
	elif [[ ${OS} == "ubuntu" ]]; then
		RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
		if [[ ${RELEASE_YEAR} -lt 18 ]]; then
			echo "Your version of Ubuntu (${VERSION_ID}) is not supported. Please use Ubuntu 18.04 or later"
			exit 1
		fi
	elif [[ ${OS} == "fedora" ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			echo "Your version of Fedora (${VERSION_ID}) is not supported. Please use Fedora 32 or later"
			exit 1
		fi
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		if [[ ${VERSION_ID} == 7* ]]; then
			echo "Your version of CentOS (${VERSION_ID}) is not supported. Please use CentOS 8 or later"
			exit 1
		fi
	elif [[ -e /etc/oracle-release ]]; then
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Unsupported distribution"
		exit 1
	fi
}

function getHomeDirForClient() {
	local CLIENT_NAME=$1
	if [ -z "${CLIENT_NAME}" ]; then
		echo "Error: getHomeDirForClient() requires a client name"
		exit 1
	fi
	if [ -e "/home/${CLIENT_NAME}" ]; then
		HOME_DIR="/home/${CLIENT_NAME}"
	elif [ "${SUDO_USER}" ]; then
		[[ "${SUDO_USER}" == "root" ]] && HOME_DIR="/root" || HOME_DIR="/home/${SUDO_USER}"
	else
		HOME_DIR="/root"
	fi
	echo "$HOME_DIR"
}

function initialCheck() {
	isRoot
	checkVirt
	checkOS
}

function installQuestions() {
	echo "Welcome to the WireGuard installer (IPv4 only)"
	echo ""

	# Detect public IPv4 and pre-fill for the user
	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	read -rp "IPv4 public address: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	# Detect public interface
	SERVER_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
	until [[ ${SERVER_PUB_NIC} =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "Public interface: " -e -i "${SERVER_NIC}" SERVER_PUB_NIC
	done

	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
		read -rp "WireGuard interface name: " -e -i wg0 SERVER_WG_NIC
	done

	until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
		read -rp "Server WireGuard IPv4: " -e -i 10.66.66.1 SERVER_WG_IPV4
	done

	# Random port
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	until [[ ${SERVER_PORT} =~ ^[0-9]+$ ]] && [ "${SERVER_PORT}" -ge 1 ] && [ "${SERVER_PORT}" -le 65535 ]; do
		read -rp "Server WireGuard port [1-65535]: " -e -i "${RANDOM_PORT}" SERVER_PORT
	done

	# DNS
	until [[ ${CLIENT_DNS_1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "First DNS resolver for clients: " -e -i 1.1.1.1 CLIENT_DNS_1
	done
	until [[ ${CLIENT_DNS_2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Second DNS resolver (optional): " -e -i 1.0.0.1 CLIENT_DNS_2
		[[ -z ${CLIENT_DNS_2} ]] && CLIENT_DNS_2="${CLIENT_DNS_1}"
	done

	until [[ ${ALLOWED_IPS} =~ ^.+$ ]]; do
		echo -e "\nAllowed IPs determine what is routed through VPN."
		read -rp "Allowed IPs for clients: " -e -i '0.0.0.0/0' ALLOWED_IPS
		[[ -z ${ALLOWED_IPS} ]] && ALLOWED_IPS="0.0.0.0/0"
	done

	echo -e "\nReady to setup your WireGuard server."
	read -n1 -r -p "Press any key to continue..."
}

function installWireGuard() {
	installQuestions

	# Install packages (per-distro)
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
		apt-get update
		apt-get install -y wireguard iptables resolvconf qrencode
	elif [[ ${OS} == 'debian' ]]; then
		if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
			echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
			apt-get update
		fi
		apt-get install -y iptables resolvconf qrencode
		apt-get install -y -t buster-backports wireguard
	elif [[ ${OS} == 'fedora' ]]; then
		dnf install -y wireguard-tools iptables qrencode
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		yum install -y wireguard-tools iptables qrencode
	elif [[ ${OS} == 'oracle' ]]; then
		dnf install -y wireguard-tools qrencode iptables
	elif [[ ${OS} == 'arch' ]]; then
		pacman -S --needed --noconfirm wireguard-tools qrencode
	fi

	mkdir -p /etc/wireguard
	chmod 600 -R /etc/wireguard/

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	# Save parameters
	cat >/etc/wireguard/params <<EOF
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

	# Create server config
	cat >"/etc/wireguard/${SERVER_WG_NIC}.conf" <<EOF
[Interface]
Address = ${SERVER_WG_IPV4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp   = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp   = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp   = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp   = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
EOF

	# Enable IPv4 forwarding
	echo "net.ipv4.ip_forward = 1" >/etc/sysctl.d/wg.conf
	sysctl --system

	systemctl start "wg-quick@${SERVER_WG_NIC}"
	systemctl enable "wg-quick@${SERVER_WG_NIC}"

	newClient
	echo -e "${GREEN}If you want to add more clients, run this script again!${NC}"

	# Check status
	if systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"; then
		echo -e "\n${GREEN}WireGuard is running.${NC}"
	else
		echo -e "\n${RED}WARNING: WireGuard does not seem to be running.${NC}"
	fi
}

function newClient() {
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	echo -e "\nClient configuration\n"
	echo "Allowed characters for client name: a-z, A-Z, 0-9, _ or - (max 15 chars)."
	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' ]]; do
		read -rp "Client name: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		[[ ${CLIENT_EXISTS} != 0 ]] && echo -e "${ORANGE}A client with that name already exists, choose another.${NC}"
	done

	# Get first free IPv4 in subnet
	for DOT_IP in {2..254}; do
		[[ $(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf") == 0 ]] && break
	done
	[[ ${DOT_IP} == 255 ]] && { echo "Subnet full (253 clients max)"; exit 1; }

	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "Client WireGuard IPv4: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/32" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		[[ ${IPV4_EXISTS} != 0 ]] && echo -e "${ORANGE}IPv4 already in use, choose another.${NC}"
	done

	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)
	HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")

	cat >"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
EOF

	# Add peer to server
	cat >>"/etc/wireguard/${SERVER_WG_NIC}.conf" <<EOF

### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32
EOF
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

	# Show QR if qrencode present
	if command -v qrencode &>/dev/null; then
		echo -e "${GREEN}\nQR Code for client configuration:\n${NC}"
		qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	fi
	echo -e "${GREEN}Client config saved to ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf${NC}"
}

function listClients() {
	NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	[[ ${NUMBER_OF_CLIENTS} -eq 0 ]] && { echo "No existing clients!"; exit 1; }
	grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
}

function revokeClient() {
	NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	[[ ${NUMBER_OF_CLIENTS} -eq 0 ]] && { echo "No existing clients!"; exit 1; }
	echo -e "\nSelect the client to revoke:"
	grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
	until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
		read -rp "Select [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
	done
	CLIENT_NAME=$(grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)
	sed -i "/^### Client ${CLIENT_NAME}\$/,/^$/d" "/etc/wireguard/${SERVER_WG_NIC}.conf"
	HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")
	rm -f "${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
	echo -e "${GREEN}Client ${CLIENT_NAME} revoked.${NC}"
}

function uninstallWg() {
	echo -e "\n${RED}WARNING: This will uninstall WireGuard and remove all configuration!${NC}"
	read -rp "Do you really want to remove WireGuard? [y/N]: " -e REMOVE
	REMOVE=${REMOVE:-n}
	if [[ $REMOVE == 'y' ]]; then
		checkOS
		systemctl stop "wg-quick@${SERVER_WG_NIC}"
		systemctl disable "wg-quick@${SERVER_WG_NIC}"
		if [[ ${OS} == 'ubuntu' || ${OS} == 'debian' ]]; then
			apt-get remove -y wireguard wireguard-tools qrencode
		elif [[ ${OS} == 'fedora' ]]; then
			dnf remove -y --noautoremove wireguard-tools qrencode
		elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
			yum remove -y --noautoremove wireguard-tools qrencode
		elif [[ ${OS} == 'oracle' ]]; then
			yum remove --noautoremove wireguard-tools qrencode
		elif [[ ${OS} == 'arch' ]]; then
			pacman -Rs --noconfirm wireguard-tools qrencode
		fi
		rm -rf /etc/wireguard
		rm -f /etc/sysctl.d/wg.conf
		sysctl --system
		echo "WireGuard uninstalled."
	else
		echo "Removal aborted!"
	fi
}

function manageMenu() {
	echo "WireGuard is already installed."
	echo "   1) Add a new user"
	echo "   2) List all users"
	echo "   3) Revoke existing user"
	echo "   4) Uninstall WireGuard"
	echo "   5) Exit"
	until [[ ${MENU_OPTION} =~ ^[1-5]$ ]]; do
		read -rp "Select an option [1-5]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1) newClient ;;
	2) listClients ;;
	3) revokeClient ;;
	4) uninstallWg ;;
	5) exit 0 ;;
	esac
}

# -------- Main --------
initialCheck
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	manageMenu
else
	installWireGuard
fi
