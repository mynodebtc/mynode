CONFIG = {}

# Enabled Features
CONFIG["rtl_enabled"] = True
CONFIG["electrs_enabled"] = True
CONFIG["explorer_enabled"] = True
CONFIG["btcrpcexplorer_enabled"] = True
CONFIG["lndhub_enabled"] = True

# myNode variables
LATEST_VERSION_URL = "https://www.mynodebtc.com/device/latest_version"
LATEST_BETA_VERSION_URL = "https://www.mynodebtc.com/device/latest_beta_version"
CHECKIN_URL = "https://www.mynodebtc.com/device_api/check_in.php"

# Bitcoin Variables
BITCOIN_ENV_FILE = "/mnt/hdd/mynode/bitcoin/env"
BITCOIN_SYNCED_FILE = "/mnt/hdd/mynode/.mynode_bitcoind_synced"

# LND Variables
LND_WALLET_FILE = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
LND_DATA_FOLDER = "/mnt/hdd/mynode/lnd/data/"

# Variables marking if app should be installed
DOJO_INSTALL_FILE =  "/mnt/hdd/mynode/settings/mynode_dojo_install"

# Other Variables
ELECTRS_ENABLED_FILE =  "/mnt/hdd/mynode/.mynode_electrs_enabled"
LNDHUB_ENABLED_FILE =   "/mnt/hdd/mynode/.mynode_lndhub_enabled"
BTCRPCEXPLORER_ENABLED_FILE = "/mnt/hdd/mynode/.mynode_btcrpceplorer_enabled"
VPN_ENABLED_FILE = "/mnt/hdd/mynode/.mynode_vpn_enabled"
NETDATA_ENABLED_FILE = "/mnt/hdd/mynode/.mynode_netdata_enabled"
MEMPOOLSPACE_ENABLED_FILE = "/mnt/hdd/mynode/.mynode_mempoolspace_enabled"
BTCPAYSERVER_ENABLED_FILE = "/mnt/hdd/mynode/.mynode_btcpayserver_enabled"
