CONFIG = {}

# MyNode variables
CHECKIN_URL = "https://www.mynodebtc.com/device_api/check_in.php"

# Bitcoin Variables
BITCOIN_ENV_FILE = "/mnt/hdd/mynode/bitcoin/env"
BITCOIN_SYNCED_FILE = "/mnt/hdd/mynode/.mynode_bitcoin_synced"
BITCOIN_SYNCED_AT_LEAST_ONCE="/mnt/hdd/mynode/.mynode_bitcoin_synced_at_least_once"
# Reindex requested in Settings ("full" or "chainstate"). mynode_gen_bitcoin_config.sh adds it to
# bitcoin.conf for one start, then moves it to the running file, which is removed once synced.
BITCOIN_REINDEX_REQUEST_FILE = "/mnt/hdd/mynode/settings/.bitcoin_reindex"
BITCOIN_REINDEX_RUNNING_FILE = "/mnt/hdd/mynode/.bitcoin_reindex_running"

# LND Variables
LND_DATA_FOLDER = "/mnt/hdd/mynode/lnd/data/"

# Variables marking if app should be installed
DOJO_INSTALL_FILE =  "/mnt/hdd/mynode/settings/mynode_dojo_install"

# Other Variables
# ...
