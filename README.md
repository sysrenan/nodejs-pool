Pool Design/Theory
------------------

The core daemons are:
```text
api - Main API for the frontend to use and pull data from.  Expects to be hosted at  /
remoteShare - Main API for consuming shares from remote/local pools.  Expects to be hosted at /leafApi
pool - Where the miners connect to.
longRunner - Database share cleanup.
payments - Handles all payments to workers.
blockManager - Unlocks blocks and distributes payments into MySQL
worker - Does regular processing of statistics and sends status e-mails for non-active miners.
```
| Service Port | Description | | | | | | | | Mining Port | Description |
|------------ | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- |
| 18980 | GRAFT Daemoon P2P Port | | | | | | | | 3333 | Low-End Hardware |
| 18981 | GRAFT Daemon RPC Port | | | | | | | | 5555 | Medium-Range Hardware |
| 18981 | GRAFT Daemon RPC Port | | | | | | | | 7777 | High-End Hardware |
| 18982 | GRAFT Daemon RPC Wallet Port | | | | | | | | 9000 | Claymore SSL |
| 8000 | remoteShare |
| 8001 | API |

Server Requirements
-------------------
* Ubuntu 16.04 (fresh installation)
* 4 Gb Ram
* 2 CPU Cores (with AES_NI)
* 60 Gb SSD-Backed Storage (not set in stone)

Pre-Installation (one liner)
----------
```bash
/usr/sbin/useradd -m graft && echo "graft ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && passwd graft
```
Interactive Installer (one liner)
------------------------
* Login as the new user: `sudo su - graft`
```bash
wget https://raw.githubusercontent.com/sysrenan/nodejs-pool/master/deployment/deploy.bash?${RANDOM} -O deploy.bash && chmod +x deploy.bash && ./deploy.bash
```

Wallet
------------
The pool is designed to have a dual-wallet design, one which is a fee wallet, one which is the live pool wallet.  The fee wallet is the default target for all fees owed to the pool owner.

The deploy script will automatically create both wallets. You will enter a wallet name during installation and the script will append `-pool` and `-fee` to the wallet as well as to the `~/walletpass` file. The password will be the same for both wallets, feel free to change as needed.

The wallet location will be: `~/<walletname>-fee` or `~/<walletname>-pool`

Final Manual Steps
------------------
* From the admin panel, you can configure all of your pool's settings for addresses, payment thresholds, etc.
* Configure email option:
```bash
UPDATE pool.config SET item_value = 'key-xxxxxxxx' WHERE module = 'general' and item = 'mailgunKey';
UPDATE pool.config SET item_value = 'https://api.mailgun.net/v3/xxxxxxx' WHERE module = 'general' and item = 'mailgunURL';
```

Configuration Details
---------------------
You should take a look at the [original wiki](https://github.com/Snipa22/nodejs-pool/wiki/Configuration-Details) for specific configuration settings in the system.


Pool Troubleshooting
---------------------
More info here: [Pool Troubleshooting](https://github.com/Snipa22/nodejs-pool#pool-troubleshooting)


Credits
---------------------
[Zone117x](https://github.com/zone117x) - Original [node-cryptonote-pool](https://github.com/zone117x/node-cryptonote-pool) from which, the stratum implementation has been borrowed.

[Mesh00](https://github.com/mesh0000) - Frontend build in Angular JS [XMRPoolUI](https://github.com/mesh0000/poolui)

[Wolf0](https://github.com/wolf9466/)/[OhGodAGirl](https://github.com/ohgodagirl) - Rebuild of node-multi-hashing with AES-NI [node-multi-hashing](https://github.com/Snipa22/node-multi-hashing-aesni)