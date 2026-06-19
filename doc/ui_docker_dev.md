# MyNode Web UI Local Docker Development

This guide describes how to run and develop the MyNode Flask/Jinja Web UI inside a localized Docker container under **Mock Mode**.

In mock mode, background processes (Bitcoin, LND, external hardware checks, etc.) are bypassed or simulated using configurable JSON fixture files. This allows front-end developer and contributors to test the UI, write styles, alter layouts, and test UI settings without needing a fully running system.

---

## Prerequisites

- **Docker** and **Docker Compose** installed on your host system.

---

## Commands

Use the predefined `Makefile` targets to manage the local Docker container:

| Target | Description |
|---|---|
| `make dev-ui-build` | Build or rebuild the UI mock docker image. |
| `make dev-ui-start` | Launch the mock UI in a background container. Opens on [http://localhost:8001](http://localhost:8001). |
| `make dev-ui-stop` | Stop and tear down the container. |
| `make dev-ui-restart` | Restart the container (useful when changing static configurations). |
| `make dev-ui-logs` | Follow container logs (shows Flask output and request details). |

---

## How it works

1. **Volume Mounts**: The container mounts your repository's local `/var/www/mynode`, `/var/pynode`, and `/usr/share/mynode_apps` folders. Any layout/template/CSS edits you make locally are reflected **instantly** (thanks to Hot Reload!).
2. **Boot bypass**: When the container boots, `init_dynamic_apps_ui.sh` mounts dynamic apps blueprints and templates without requiring the full installation logic.
3. **Mocking Interceptor**: Inside `mynode.py`, if `MYNODE_UI_MOCK=1` is preset, the app runs `mock_bootstrap.enable_mock_mode()` as the first line of code. This patches the core modules inside `sys.modules` (`device_info`, `bitcoin_info`, `lightning_info`, etc.) with mock handlers.
4. **State Persistence**: A mutable, in-memory mock state keeps track of status alterations, toggled settings, and service activations so page refreshes and service enablement updates behave realistically.
5. **Auto-Login Bypass**: Authentication checks are fully bypassed. A Flask `before_request` hook forces the session to have `session["logged_in"] = True`, bypasses PAM authenticators entirely, and routes directly to the operational dashboard.

---

## Scenario / Fixture Selection

Mock data is loaded from JSON files based on the scenario directory selected. By default, the `stable-synced` scenario is used.

### File Structure
The mock scenario directory represents a snapshot of the backend state:
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/device.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/device.json) — CPU, RAM, IP address, device type, warnings, and serial.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/bitcoin.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/bitcoin.json) — Sync progress, block height, peer connections, mempool and fees.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/lightning.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/lightning.json) — Wallet availability, wallet size, active channels, node alias, active peers.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/applications.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/applications.json) — Dynamic apps list, versions, capability, and prerequisites.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/services.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/services.json) — Service enabling/disabling indicator colors.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/ui_settings.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/ui_settings.json) — Default selected theme or currency.
* [rootfs/standard/var/pynode/mock_fixtures/stable-synced/logs.json](rootfs/standard/var/pynode/mock_fixtures/stable-synced/logs.json) — Mock service output messages.

### Custom Scenarios

If you want to construct different system states (e.g. debugging a syncing node, simulated storage warnings):
1. Create a new directory inside `/rootfs/standard/var/pynode/mock_fixtures/<your-scenario-name>/`.
2. Add custom versions of the JSON files (`device.json`, `bitcoin.json`, etc.) matching only the changes you wish to override.
3. Start the UI container with the environment variable `MYNODE_UI_SCENARIO` set:
   ```bash
   MYNODE_UI_SCENARIO=syncing-blocks docker compose -f docker-compose.ui.yml up -d
   ```

---

## Environment Customization

The following environment variables can be altered in your shell or inside `docker-compose.ui.yml`:

- `MYNODE_UI_PORT` — The port on which the UI will be served on the host machine (defaults to `8000`).
- `MYNODE_UI_SCENARIO` — The directory name of the mock fixtures to read (defaults to `stable-synced`).
- `MYNODE_UI_RELOAD` — Set to `1` (default) to run Flask with `debug=True` and hot reloading enabled.
