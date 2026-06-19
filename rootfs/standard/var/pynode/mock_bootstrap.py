import sys
import logging
from mock_state import MockState

logger = logging.getLogger("mynode_mock_bootstrap")

def enable_mock_mode():
    logger.info("Enabling mock mode for MyNode Web UI")
    
    # 1. Initialize MockState
    state = MockState.get_instance()
    
    # 2. Patch low-level helper modules first so any subsequent star imports copy the patched versions!
    import device_info
    import bitcoin_info
    import drive_info
    
    # Patch device_info
    device_info.get_mynode_status = lambda: state.get("device").get("status", "stable")
    device_info.get_current_version = lambda: state.get("device").get("current_version", "0.3.0")
    device_info.get_latest_version = lambda: state.get("device").get("latest_version", "0.3.0")
    device_info.get_current_beta_version = lambda: state.get("device").get("current_beta_version", "0.3.0-beta")
    device_info.get_latest_beta_version = lambda: state.get("device").get("latest_beta_version", "0.3.0-beta")
    device_info.get_system_uptime_in_seconds = lambda: state.get("device").get("uptime_seconds", 123456)
    device_info.get_system_uptime = lambda: "Uptime: Mock Day, 10 hours"
    device_info.get_system_date = lambda: "2026-06-14"
    device_info.get_local_ip = lambda: state.get("device").get("ip", "127.0.0.1")
    device_info.get_device_serial = lambda: state.get("device").get("serial", "MYNODE-MOCK-SERIAL-999")
    device_info.get_device_type = lambda: state.get("device").get("type", "raspi4")
    device_info.get_device_arch = lambda: state.get("device").get("arch", "aarch64")
    device_info.get_debian_version = lambda: int(state.get("device").get("debian_version", 12))
    device_info.get_debian_codename = lambda: state.get("device").get("debian_codename", "bookworm")
    device_info.get_cpu_usage = lambda: state.get("device").get("cpu_usage", 15.0)
    device_info.get_ram_usage = lambda: state.get("device").get("ram_usage", 45.0)
    device_info.get_device_temp = lambda: state.get("device").get("temp", "45.2 C")
    device_info.get_firewall_rules = lambda: []
    device_info.get_check_in_data = lambda: {}
    device_info.is_upgrade_running = lambda: False
    device_info.did_upgrade_fail = lambda: False
    device_info.has_product_key = lambda: state.get("device").get("has_product_key", True)
    device_info.is_valid_product_key = lambda: state.get("device").get("is_valid_product_key", True)
    device_info.skipped_product_key = lambda: state.get("device").get("skipped_product_key", False)
    device_info.reboot_device = lambda: True
    device_info.shutdown_device = lambda: True
    
    # UI settings from device_info
    device_info.read_ui_settings = lambda: state.get("ui_settings")
    
    def mock_get_ui_setting(keyword):
        return state.get("ui_settings").get(keyword, False)
    device_info.get_ui_setting = mock_get_ui_setting
    
    def mock_toggle_ui_setting(keyword):
        ui = state.get("ui_settings")
        current_val = ui.get(keyword, False)
        if isinstance(current_val, str):
            new_val = "false" if current_val == "true" else "true"
        elif isinstance(current_val, bool):
            new_val = not current_val
        else:
            new_val = True
        ui[keyword] = new_val
        state.set_data("ui_settings", ui)
        return new_val
    device_info.toggle_ui_setting = mock_toggle_ui_setting

    def mock_set_ui_setting(keyword, value):
        ui = state.get("ui_settings")
        ui[keyword] = value
        state.set_data("ui_settings", ui)
        return value
    device_info.set_ui_setting = mock_set_ui_setting
    
    device_info.get_flask_secret_key = lambda: "mock-flask-secret-key-12345678"
    device_info.get_flask_session_timeout = lambda: (30, 0)

    # Patch bitcoin_info
    bitcoin_info.is_bitcoin_synced = lambda: state.get("bitcoin").get("synced")
    bitcoin_info.get_bitcoin_status = lambda: state.get("bitcoin").get("status")
    bitcoin_info.get_bitcoin_blockchain_info = lambda: state.get("bitcoin")
    bitcoin_info.get_bitcoin_recent_blocks = lambda: state.get("bitcoin").get("recent_blocks")
    bitcoin_info.get_bitcoin_peers = lambda: state.get("bitcoin").get("peers")
    bitcoin_info.get_bitcoin_peer_count = lambda: state.get("bitcoin").get("peer_count")
    bitcoin_info.get_bitcoin_network_info = lambda: state.get("bitcoin").get("network_info")
    def mock_get_bitcoin_mempool_info():
        info = state.get("bitcoin").get("mempool_info", {})
        count = info.get("size", 0)
        num_bytes = info.get("bytes", 0)
        mb = round(float(num_bytes / 1000 / 1000), 2)
        return {
            "size": count,
            "count": count,
            "bytes": num_bytes,
            "display_bytes": f"{mb} MB"
        }

    bitcoin_info.get_bitcoin_mempool_info = mock_get_bitcoin_mempool_info
    bitcoin_info.get_bitcoin_recommended_fees = lambda: state.get("bitcoin").get("recommended_fees")
    bitcoin_info.get_bitcoin_wallets = lambda: []
    bitcoin_info.get_bitcoin_version = lambda: state.get("bitcoin").get("version")
    bitcoin_info.get_bitcoin_disk_usage = lambda: state.get("bitcoin").get("disk_usage")
    bitcoin_info.get_mynode_block_height = lambda: state.get("bitcoin").get("mynode_block_height")
    bitcoin_info.get_bitcoin_block_height = lambda: state.get("bitcoin").get("block_height")
    bitcoin_info.get_bitcoin_sync_progress = lambda: state.get("bitcoin").get("sync_progress")
    bitcoin_info.run_bitcoincli_command = lambda cmd: f"Mock response for command: {cmd}"

    # Patch drive_info
    drive_info.get_data_drive_usage = lambda: f"{state.get('device').get('data_drive', {}).get('percent', 0)}%"
    drive_info.get_data_drive_usage_details = lambda: state.get("device").get("data_drive", {})
    drive_info.get_os_drive_usage = lambda: f"{state.get('device').get('os_drive', {}).get('percent', 0)}%"
    drive_info.get_os_drive_usage_details = lambda: state.get("device").get("os_drive", {})

    # Now load and patch other modules (which will get the pre-patched device_info, bitcoin_info, drive_info!)
    import lightning_info
    import application_info
    import systemctl_info
    import enable_disable_functions
    import user_management
    
    # Patch thread_functions and electrum_info
    try:
        import thread_functions
        thread_functions.get_has_updated_btc_info = lambda: True
    except ImportError:
        pass

    try:
        import electrum_info
        electrum_info.is_electrs_active = lambda: state.get("services").get("electrs", {}).get("running", True)
    except ImportError:
        pass
    
    try:
        import price_info
    except ImportError:
        price_info = None

    # Patch lightning_info
    lightning_info.lnd_wallet_exists = lambda: state.get("lightning").get("wallet_exists")
    lightning_info.is_lnd_logged_in = lambda: state.get("lightning").get("logged_in")
    lightning_info.is_lnd_ready = lambda: state.get("lightning").get("ready")
    lightning_info.get_lnd_status = lambda: state.get("lightning").get("status")
    lightning_info.get_lnd_status_color = lambda: state.get("lightning").get("status_color")
    lightning_info.get_lnd_version = lambda: state.get("lightning").get("version")
    lightning_info.get_loop_version = lambda: state.get("lightning").get("loop_version")
    lightning_info.get_pool_version = lambda: state.get("lightning").get("pool_version")
    lightning_info.get_lnd_deposit_address = lambda: state.get("lightning").get("deposit_address")
    lightning_info.get_lightning_info = lambda: state.get("lightning").get("info")
    lightning_info.get_lightning_peers = lambda: state.get("lightning").get("peers")
    lightning_info.get_lightning_channels = lambda: state.get("lightning").get("channels")
    lightning_info.get_lightning_balance_info = lambda: state.get("lightning").get("balance_info")
    lightning_info.get_lightning_transactions = lambda: state.get("lightning").get("transactions")
    lightning_info.get_lightning_payments = lambda: state.get("lightning").get("payments")
    lightning_info.get_lightning_invoices = lambda: state.get("lightning").get("invoices")

    # Patch application_info
    def mock_get_all_applications(order_by="none", include_status=False):
        apps = state.get("applications")
        # In mock state, applications is a dict. Convert to list-of-dicts
        apps_list = list(apps.values())
        if order_by == "alphabetic":
            apps_list.sort(key=lambda x: x.get("name", ""))
        elif order_by == "homepage":
            apps_list.sort(key=lambda x: x.get("homepage_order", 999))
        return apps_list

    application_info.get_all_applications = mock_get_all_applications
    application_info.get_application = lambda name: state.get("applications").get(name)
    application_info.is_application_valid = lambda name: name in state.get("applications")
    application_info.get_application_status = lambda name: state.get("applications").get(name, {}).get("status", "Unknown")
    application_info.get_application_status_color = lambda name: state.get("applications").get(name, {}).get("status_color", "red")
    application_info.get_application_log = lambda name, lines=100: state.get("logs").get(name, f"Mock log for {name}")
    application_info.get_application_sso_token = lambda name: "mock-sso-token"
    application_info.get_application_sso_token_enabled = lambda name: False
    application_info.is_installed = lambda name: state.get("applications").get(name, {}).get("is_installed", False)
    application_info.is_service_enabled = lambda name: state.get("services").get(name, {}).get("enabled", False)

    # Patch systemctl_info
    systemctl_info.get_service_status_basic_text = lambda name: state.get("services").get(name, {}).get("text", "In-active")
    systemctl_info.get_service_status_color = lambda name: state.get("services").get(name, {}).get("color", "red")
    systemctl_info.get_service_status_code = lambda name: 0 if state.get("services").get(name, {}).get("running", False) else 3

    # Patch enable_disable_functions
    def mock_enable_service(name):
        srv = state.get("services")
        if name in srv:
            srv[name]["enabled"] = True
            srv[name]["running"] = True
            srv[name]["text"] = "Running"
            srv[name]["color"] = "green"
        apps = state.get("applications")
        if name in apps:
            apps[name]["is_installed"] = True
            apps[name]["is_running"] = True
            apps[name]["status"] = "Up"
            apps[name]["status_color"] = "green"
        state.set_data("services", srv)
        state.set_data("applications", apps)
        return True
    enable_disable_functions.enable_service = mock_enable_service

    def mock_disable_service(name):
        srv = state.get("services")
        if name in srv:
            srv[name]["enabled"] = False
            srv[name]["running"] = False
            srv[name]["text"] = "Stopped"
            srv[name]["color"] = "red"
        apps = state.get("applications")
        if name in apps:
            apps[name]["is_running"] = False
            apps[name]["status"] = "Down"
            apps[name]["status_color"] = "red"
        state.set_data("services", srv)
        state.set_data("applications", apps)
        return True
    enable_disable_functions.disable_service = mock_disable_service

    enable_disable_functions.restart_service = lambda name, timer=None: True
    enable_disable_functions.restart_application = lambda name: True

    # Patch price_info if loaded
    if price_info:
        price_info.get_latest_price = lambda: 65123.45
        price_info.get_price_diff_24hrs = lambda: 120.50
        price_info.get_price_up_down_flat_24hrs = lambda: "up"
        price_info.update_price_info = lambda: None

    # Patch user_management
    user_management.check_logged_in = lambda: True
    user_management.is_logged_in = lambda: True
    user_management.login = lambda pwd: True
    user_management.logout = lambda: True
