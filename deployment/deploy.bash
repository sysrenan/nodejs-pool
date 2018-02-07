#!/bin/bash
#
# Feb 2018 - Modified by: sysrenan (https://github.com/sysrenan)
#
clear
echo "This assumes that you are doing a green-field install.  If you're not, please exit in the next 15 seconds."
sleep 15
echo "Continuing install, this will prompt you for your password if you're not already running as root and you didn't enable passwordless sudo.  Please do not run me as root!"
if [[ `whoami` == "root" ]]; then
    echo "You ran me as root! Do not run me as root!"
    exit 1
fi

clear
echo ":: AUTO SETUP ::"
echo "** We do not collect any of this data, it is only used for a smoother setup."
echo " "

echo -n "Domain Name (example.com): "
read domainName
echo -n "Admin Email: "
read adminEmail
echo -n "Email From Name: "
read fromName
echo -n "Enter an Administrator Password: "
read adminPass

echo -n "Would you like to create a new GRAFT Wallet? y/n: "
read newWallet
if [[ "${newWallet}" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
	echo -n "Enter Wallet Name (mywallet): "
	read walletName
	echo -n "Enter Wallter Password (alphanumeric): "
	read walletPass
fi

# DEFINE
CURUSER=$(whoami)
ROOT_SQL_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
POOL_SQL_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
TIMEZONE="Etc/UTC"

# Set Timezone and Update
sudo timedatectl set-timezone ${TIMEZONE}
sudo apt-get update

# Database Installation
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${ROOT_SQL_PASS}"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${ROOT_SQL_PASS}"
echo -e "[client]\nuser=root\npassword=${ROOT_SQL_PASS}" | sudo tee /root/.my.cnf

# Install required packages
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install git python-virtualenv python3-virtualenv curl ntp doxygen graphviz build-essential screen cmake pkg-config libboost-all-dev libevent-dev libunbound-dev libminiupnpc-dev libunwind8-dev liblzma-dev libldns-dev libexpat1-dev libgtest-dev mysql-server lmdb-utils libzmq3-dev

# Install NodeJS Pool from GIT
cd ~
git clone https://github.com/sysrenan/nodejs-pool.git  # Change this depending on how the deployment goes.
cd /usr/src/gtest
sudo cmake .
sudo make
sudo mv libg* /usr/lib/
cd ~
sudo systemctl enable ntp

# Install GraftNetwork Project
cd /usr/local/src
sudo git clone https://github.com/graft-project/GraftNetwork.git
cd GraftNetwork
./install_dependencies.sh 
sudo make -j$(nproc)
sudo cp build/release/bin/* /usr/local/bin/
sudo cp ~/nodejs-pool/deployment/graft/graft.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable graft
sudo systemctl start graft

# Wallet used for GRAFT Fees Collection
/usr/local/src/GraftNetwork/build/release/bin/graft-wallet-cli --generate-new-wallet ~/${walletName}-fee --password="${walletPass}" --mnemonic-language "English" 2>&1 &
echo "${walletPass}" > ~/walletpass-fee
chmod 0400 ~/walletpass-fee

# Wallet used for GRAFT RPC Pool (payment distribution)
/usr/local/src/GraftNetwork/build/release/bin/graft-wallet-cli --generate-new-wallet ~/${walletName}-pool --password="${walletPass}" --mnemonic-language "English" 2>&1 &
echo "${walletPass}" > ~/walletpass-pool
chmod 0400 ~/walletpass-pool

# Install NVM
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
source ~/.nvm/nvm.sh
nvm install v8.9.3
cd ~/nodejs-pool
npm install
npm install -g pm2

# Generate SSL CERT
openssl req -subj "/C=IT/ST=Pool/L=Daemon/O=Mining Pool/CN=mining.pool" -newkey rsa:2048 -nodes -keyout cert.key -x509 -out cert.pem -days 36500

# Changing Config Settings
mkdir ~/pool_db/
sed -r "s/(\"db_storage_path\": ).*/\1\"\/home\/${CURUSER}\/pool_db\/\",/" ~/nodejs-pool/config_example.json > config.json

# Install Pool UI
cd ~
git clone https://github.com/sysrenan/poolui.git
# Change config files
sed -i "s@CHANGEPASS@${POOL_SQL_PASS}@g" ~/nodejs-pool/config.json
sed -i "s@example.com@pool.${domainName}@g" ~/nodejs-pool/config.json
sed -i "s@CHANGEPASS@${POOL_SQL_PASS}@g" ~/nodejs-pool/deployment/base.sql
sed -i "s@CHANGEPASS@${POOL_SQL_PASS}@g" ~/nodejs-pool/config_example.json
sed -i "s@example.com@pool.${domainName}@g" ~/nodejs-pool/debug_scripts/socket_io.html
sed -i "s@example.com@${domainName}@g" ~/poolui/app/globals.js
sed -i "s@example.com@${domainName}@g" ~/poolui/app/globals.default.js

cd ~/poolui
npm install
./node_modules/bower/bin/bower update
./node_modules/gulp/bin/gulp.js build
cd build
sudo ln -s `pwd` /var/www

# Install CADDY Web Server
if [[ "$(uname -m)" == *64* ]]; then
	caddy_arch="amd64"
elif [[ "$(uname -m)" == *86* ]]; then
	caddy_arch="386"
else
	echo "Aborted, unsupported or unknown architecture: $unamem"
	return 2
fi
qs="license=personal&plugins=http.proxyprotocol,http.ratelimit"
caddy_url="https://caddyserver.com/download/linux/${caddy_arch}${caddy_arm}?${qs}"
CADDY_DOWNLOAD_DIR=$(mktemp -d)
cd $CADDY_DOWNLOAD_DIR
curl -sL "${caddy_url}" | tar -xz caddy init/linux-systemd/caddy.service
sudo mv caddy /usr/local/bin
sudo chown root:root /usr/local/bin/caddy
sudo chmod 755 /usr/local/bin/caddy
sudo setcap 'cap_net_bind_service=+ep' /usr/local/bin/caddy
sudo groupadd -g 33 www-data
sudo useradd -g www-data --no-user-group --home-dir /var/www --no-create-home --shell /usr/sbin/nologin --system --uid 33 www-data
sudo mkdir /etc/caddy
sudo chown -R root:www-data /etc/caddy
sudo mkdir /etc/ssl/caddy
sudo chown -R www-data:root /etc/ssl/caddy
sudo chmod 0770 /etc/ssl/caddy
sudo cp ~/nodejs-pool/deployment/caddy/caddyfile /etc/caddy/Caddyfile
sudo chown www-data:www-data /etc/caddy/Caddyfile
sudo chmod 444 /etc/caddy/Caddyfile
sudo sh -c "sed 's/ProtectHome=true/ProtectHome=false/' init/linux-systemd/caddy.service > /etc/systemd/system/caddy.service"
sudo chown root:root /etc/systemd/system/caddy.service
sudo chmod 644 /etc/systemd/system/caddy.service
sudo systemctl daemon-reload
sudo systemctl enable caddy.service
sudo systemctl start caddy.service
rm -rf $CADDY_DOWNLOAD_DIR

# Defining ENV Vars
cd ~
sudo env PATH=$PATH:`pwd`/.nvm/versions/node/v8.9.3/bin `pwd`/.nvm/versions/node/v8.9.3/lib/node_modules/pm2/bin/pm2 startup systemd -u ${CURUSER} --hp `pwd`

# Install PM2
cd ~/nodejs-pool
sudo chown -R $CURUSER. ~/.pm2
echo "installing pm2-logrotate... might take few minutes, hang in there!"
pm2 install pm2-logrotate &
sleep 20s

# Configuring Database
mysql -u root --password=${ROOT_SQL_PASS} < deployment/base.sql
mysql -u root --password=${ROOT_SQL_PASS} pool -e "INSERT INTO pool.config (module, item, item_value, item_type, Item_desc) VALUES ('api', 'authKey', '`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`', 'string', 'Auth key sent with all Websocket frames for validation.')"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "INSERT INTO pool.config (module, item, item_value, item_type, Item_desc) VALUES ('api', 'secKey', '`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`', 'string', 'HMAC key for Passwords.  JWT Secret Key.  Changing this will invalidate all current logins.')"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = '${adminEmail}' WHERE module = 'general' and item = 'adminEmail';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = '${adminEmail}' WHERE module = 'general' and item = 'emailFrom';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = '`cat ~/${walletName}-pool.address.txt`' WHERE module = 'pool' and item = 'address';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = '`cat ~/${walletName}-fee.address.txt`' WHERE module = 'payout' and item = 'feeAddress';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = 'http://127.0.0.1:8000/leafApi' WHERE module = 'general' and item = 'shareHost';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.config SET item_value = '- ${fromName}' WHERE module = 'general' and item = 'emailSig';"
mysql -u root --password=${ROOT_SQL_PASS} pool -e "UPDATE pool.users SET email = '${adminPass}' WHERE id = '1';"

# Install LMDB Tools
bash ~/nodejs-pool/deployment/install_lmdb_tools.sh
sleep 10s

# Defining ENV Vars
cd ~/nodejs-pool/sql_sync/
env PATH=$PATH:`pwd`/.nvm/versions/node/v8.9.3/bin node sql_sync.js
source ~/.bashrc
source ~/.profile
source /etc/profile

# Start API Module
cd ~/nodejs-pool
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start /usr/local/src/GraftNetwork/build/release/bin/graft-wallet-rpc -- --rpc-bind-port 18982 --password-file ~/walletpass-pool --wallet-file ~/${walletName}-pool --disable-rpc-login --trusted-daemon &

sleep 10s
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=api --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=api &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=blockManager --log-date-format="YYYY-MM-DD HH:mm Z"  -- --module=blockManager &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=worker --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=worker &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=payments --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=payments &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=remoteShare --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=remoteShare &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=longRunner --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=longRunner &
/home/graft/.nvm/versions/node/v8.9.3/bin/pm2 start init.js --name=pool --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=pool &

sleep 10s
clear
cd ~
echo ":: REPORT ::"
echo "
Domain: ${domainName}
Email: ${adminEmail}

Admin Panel: http://${domainName}/admin.html
User: Administrator
Pass: ${adminPass}

MySQL User: root
MySQL DB: <all>
MySQL Pass: ${ROOT_SQL_PASS}

MySQL User: pool
MySQL DB: pool
MySQL Pass: ${POOL_SQL_PASS}

Wallet Location: ${PWD}/${walletName}
Wallet Pass: ${walletPass}
** Please backup your wallet!!!

Config Files:
${PWD}/nodejs-pool/config.json
${PWD}/nodejs-pool/coinConfig.json
${PWD}/poolui/build/globals.js
${PWD}/poolui/build/globals.default.js

PM2 Logs:
${PWD}/.pm2/logs/
"

echo "You're setup!  Please read the rest of the readme for the remainder of your setup and configuration."