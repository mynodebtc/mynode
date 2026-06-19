import os
import json
import logging
from copy import deepcopy

logger = logging.getLogger("mynode_mock_state")

class MockState:
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self.scenario = os.environ.get("MYNODE_UI_SCENARIO", "stable-synced")
        self.fixtures_dir = "/var/pynode/mock_fixtures"
        self.state = {}
        self.load_scenario(self.scenario)

    def load_scenario(self, scenario_name):
        self.scenario = scenario_name
        self.state = {
            "device": self._get_default_device(),
            "bitcoin": self._get_default_bitcoin(),
            "lightning": self._get_default_lightning(),
            "applications": self._get_default_applications(),
            "services": self._get_default_services(),
            "ui_settings": self._get_default_ui_settings(),
            "logs": self._get_default_logs()
        }
        
        scenario_path = os.path.join(self.fixtures_dir, scenario_name)
        if os.path.isdir(scenario_path):
            logger.info(f"Loading mock scenario state from {scenario_path}")
            for key in self.state.keys():
                file_path = os.path.join(scenario_path, f"{key}.json")
                if os.path.isfile(file_path):
                    try:
                        with open(file_path, "r") as f:
                            self.state[key].update(json.load(f))
                    except Exception as e:
                        logger.error(f"Error loading fixture {file_path}: {e}")
        else:
            logger.warning(f"Scenario path {scenario_path} not found. Using default mock state.")

    def get(self, domain):
         return deepcopy(self.state.get(domain, {}))

    def update(self, domain, key, value):
         if domain not in self.state:
              self.state[domain] = {}
         self.state[domain][key] = value

    def set_data(self, domain, data):
         self.state[domain] = deepcopy(data)

    def _get_default_device(self):
        return {
            "status": "stable",
            "current_version": "0.3.0",
            "latest_version": "0.3.0",
            "current_beta_version": "0.3.0-beta",
            "latest_beta_version": "0.3.0-beta",
            "uptime_seconds": 123456,
            "ip": "127.0.0.1",
            "temp": "45.2 C",
            "serial": "MYNODE-MOCK-SERIAL-999",
            "type": "raspi4",
            "arch": "aarch64",
            "debian_version": "12",
            "debian_codename": "bookworm",
            "cpu_usage": 12.5,
            "ram_usage": 42.1,
            "os_drive": {"total": "59.2 GB", "used": "15.4 GB", "free": "41.6 GB", "percent": 27},
            "data_drive": {"total": "931.5 GB", "used": "612.4 GB", "free": "319.1 GB", "percent": 65},
            "warnings": [],
            "has_product_key": True,
            "is_valid_product_key": True,
            "skipped_product_key": False
        }

    def _get_default_bitcoin(self):
        return {
            "synced": True,
            "sync_progress": 1.0,
            "status": "Up",
            "version": "26.0",
            "block_height": 840000,
            "mynode_block_height": 840000,
            "difficulty": 83123456789.0,
            "peer_count": 12,
            "network_info": {"connections": 12, "version": 260000},
            "mempool_info": {"size": 4321, "bytes": 1234567},
            "recommended_fees": {"fastestFee": 15, "halfHourFee": 12, "hourFee": 10, "economyFee": 5, "minimumFee": 1},
            "disk_usage": "600 GB",
            "peers": [
                {"id": 1, "addr": "1.2.3.4:8333", "subver": "/Satoshi:26.0.0/", "inbound": False},
                {"id": 2, "addr": "5.6.7.8:8333", "subver": "/Satoshi:25.0.0/", "inbound": True}
            ],
            "recent_blocks": [
                {"height": 840000, "hash": "000000000000000000010abcde...", "time": 1718300000},
                {"height": 839999, "hash": "000000000000000000021ffeed...", "time": 1718299400}
            ]
        }

    def _get_default_lightning(self):
        return {
            "wallet_exists": True,
            "logged_in": True,
            "ready": True,
            "status": "Up",
            "status_color": "green",
            "version": "0.17.4-beta",
            "loop_version": "0.26.4-beta",
            "pool_version": "0.28.2-beta",
            "deposit_address": "tb1qmockaddresslnddepositaddress1234567",
            "info": {
                "identity_pubkey": "02mockpubkeylndnode1234567890abcdef1234567890abcdef",
                "alias": "MyNode-Mock",
                "num_active_channels": 4,
                "num_peers": 8,
                "block_height": 840000,
                "synced_to_chain": True,
                "synced_to_graph": True
            },
            "balance_info": {
                "wallet_balance": 1500000,
                "channel_balance": 3500000,
                "pending_channel_balance": 0
            },
            "channels": [
                {"active": True, "remote_pubkey": "03peer1pubkey...", "capacity": 2000000, "local_balance": 1200000, "remote_balance": 800000, "chan_id": "123456780"},
                {"active": True, "remote_pubkey": "02peer2pubkey...", "capacity": 3000000, "local_balance": 2300000, "remote_balance": 700000, "chan_id": "987654320"}
            ],
            "peers": [
                {"pub_key": "03peer1pubkey...", "address": "1.1.1.1:9735"},
                {"pub_key": "02peer2pubkey...", "address": "2.2.2.2:9735"}
            ],
            "transactions": [],
            "payments": [],
            "invoices": []
        }

    def _get_default_applications(self):
        return {
            "lnd": {
                "name": "LND",
                "short_name": "lnd",
                "is_installed": True,
                "is_running": True,
                "can_enable_disable": True,
                "status": "Up",
                "status_color": "green",
                "supported_archs": ["all"],
                "requires_bitcoin": True,
                "requires_lightning": False
            },
            "electrs": {
                "name": "Electrs",
                "short_name": "electrs",
                "is_installed": True,
                "is_running": True,
                "can_enable_disable": True,
                "status": "Up",
                "status_color": "green",
                "supported_archs": ["all"],
                "requires_bitcoin": True,
                "requires_lightning": False
            },
            "lndg": {
                "name": "LNDg",
                "short_name": "lndg",
                "is_installed": True,
                "is_running": True,
                "can_enable_disable": True,
                "status": "Up",
                "status_color": "green",
                "supported_archs": ["all"],
                "requires_bitcoin": True,
                "requires_lightning": True
            }
        }

    def _get_default_services(self):
        return {
            "bitcoin": {"running": True, "enabled": True, "color": "green", "text": "Running"},
            "lnd": {"running": True, "enabled": True, "color": "green", "text": "Running"},
            "electrs": {"running": True, "enabled": True, "color": "green", "text": "Running"},
            "lndg": {"running": True, "enabled": True, "color": "green", "text": "Running"}
        }

    def _get_default_ui_settings(self):
        return {
            "theme": "dark",
            "currency": "USD",
            "pin_bitcoin": "true",
            "pin_lnd": "true",
            "pin_electrs": "false"
        }

    def _get_default_logs(self):
        return {
            "bitcoin": "Bitcoin Mock Log - everything is looking stable.\nBlock 840000 found!\n",
            "lnd": "LND Mock Log - channels active.\nsyncing to chain...\nReady for payments!\n",
            "lndg": "LNDg Mock Log - running and collecting fee suggestions.\n"
        }
