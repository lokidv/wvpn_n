
```
sudo apt update && upgrade -y


curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh


chmod +x openvpn-install.sh


./openvpn-install.sh

git clone https://github.com/lokidv/oinstaller.git && mv oinstaller/* /root/ && chmod +x install.sh && chmod +x install2.sh

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update
sudo apt-get install nodejs -y


sudo npm install pm2 -g

git clone https://github.com/lokidv/ovpn.git
mv ovpn/ /home
cd /home
mkdir bvpn
mv ovpn/* bvpn/
rm -r ovpn/


cd bvpn/
npm i
mv /root/openvpn-install.sh /home/bvpn/

nano /etc/systemd/system/bvpn.service

[Unit]
Description=Tunnel WireGuard with udp2raw
After=network.target

[Service]
Type=simple
User=root
ExecStart=sudo node /home/bvpn/main.js
Restart=no

[Install]
WantedBy=multi-user.target

systemctl enable --now bvpn.service 


or


pm2 start main.js
pm2 list
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

