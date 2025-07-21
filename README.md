
```
recommand
wget https://raw.githubusercontent.com/lokidv/wvpn/refs/heads/main/install_wire.sh && sudo chmod +x install_wire.sh && sudo ./install_wire.sh
wget https://raw.githubusercontent.com/lokidv/wvpn/refs/heads/main/tun.sh && sudo chmod +x tun.sh && sudo ./tun.sh
sudo apt update && sudo apt upgrade -y


nano /etc/resolv.conf

nameserver 1.1.1.1


sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update
sudo apt-get install nodejs -y

sudo apt install nano -y
sudo apt install git -y
sudo apt install cron -y




git clone https://github.com/lokidv/wvpn.git
mv wvpn/ /home
cd /home
cd wvpn




npm i

chmod +x wireguard-install.sh
./wireguard-install.sh
nano /etc/systemd/system/wvpn.service
```

```
[Unit]
Description=Tunnel WireGuard with udp2raw
After=network.target

[Service]
Type=simple
User=root
ExecStart=sudo node /home/wvpn/main.js
Restart=no

[Install]
WantedBy=multi-user.target
```
```
systemctl enable --now wvpn.service 
systemctl status wvpn.service

when you want to restart

systemctl restart wvpn.service

cd

nano /etc/sysctl.d/99-sysctl.conf
rm /home/wvpn/wireguard-install.sh  && wget https://github.com/lokidv/wvpn/raw/main/wireguard-install.sh -O /home/wvpn/wireguard-install.sh && chmod +x /home/wvpn/wireguard-install.sh && sudo systemctl restart wvpn.service
* * * * * /bin/systemctl is-active --quiet udp2raw.service || /bin/systemctl 
or



```
for crontab

```
export VISUAL=nano; crontab -e

* 12 * * * reboot


```

for transfer
```
cd /
tar czvf openvpn_backup.tar.gz /etc/openvpn/ /etc/openvpn/easy-rsa/
scp openvpn_backup.tar.gz root@ip:/root
tar xzvf openvpn_backup.tar.gz
sudo systemctl stop openvpn@server.service
rm -r /etc/openvpn/
mv etc/openvpn /etc
nano /etc/systemd/system/udp2raw.service
```

