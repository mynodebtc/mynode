# myNode UI Dev Mode (mocked backend)

Run the real myNode web UI in a Docker container with a fully mocked backend —
no bitcoind, no LND, no systemd, no real device. For developing and testing UI
changes (templates, CSS, JS, Flask routes) with instant hot reload.

## Quick start

```bash
make dev-ui          # from the repo root; builds + starts the container
```

Open **http://localhost:8888** and log in with password **`bolt`**
(configurable via `DEV_PASSWORD` in docker-compose.yml; set `DEV_AUTOLOGIN=1`
to skip login entirely).

Other targets: `make dev-ui-build`, `make dev-ui-shell`, `make dev-ui-clean`.

Edit any file under `rootfs/standard/var/www/mynode/` (templates, static
assets, python) or `rootfs/standard/var/pynode/` on the host — templates apply
on refresh, python triggers Flask auto-reload. The source is mounted
**read-only**, so nothing in this container can modify real code. `git status`
stays clean.

## The DEV panel

Every page gets a floating **DEV** button (bottom-right) that opens the state
switcher:

- **Device state** — flip `/tmp/.mynode_status` to any state (`stable`,
  `drive_missing`, `drive_formatting`, `choose_network`, `quicksync_*`,
  `upgrading`, `shutting_down`, ...) to render every state page.
- **Bitcoin** — synced / syncing at an arbitrary progress (renders the real
  syncing page), or the "Launching MyNode Services" starting page.
- **Lightning** — LND ready/not-ready, wallet exists/missing (wallet-create flow).
- **Warnings** — undervoltage / throttled / capped / fsck / usb warning pages.
- **System** — drive-almost-full error, upgrade banner, premium vs community
  edition, simulated reboot/shutdown, and **RESET ALL** back to the golden state.
- **Apps** — one-click install/uninstall (marker files only, no real install).

Everything the panel does is also available as plain HTTP endpoints under
`/dev/...` (no auth) — see `dev_blueprint.py`. Examples:

```bash
curl 'localhost:8888/dev/state?value=drive_missing'
curl 'localhost:8888/dev/sync?synced=0&progress=0.62'
curl 'localhost:8888/dev/app?name=specter&installed=1'
curl 'localhost:8888/dev/service?name=electrs&status=failed'
curl 'localhost:8888/dev/reset'
```

The full install flow also works end-to-end from the normal UI: installing an
app from the marketplace shows the real "Installing..." page with a (fake)
live install log, a simulated reboot, and the app appears installed afterward.
Reboot/shutdown from settings play out the real reboot page (the mock resets a
fake boot-time file; the page redirects home when it sees uptime decrease).

## How it works (architecture)

**Zero changes to real code.** The container runs the unmodified Flask app
with three mock layers around it:

1. **PYTHONPATH shim (`mock_pynode/`)** — sits before `/var/www/mynode` and
   `/var/pynode` on the python path, so `import bitcoin_info` etc. resolve to
   the mocks. Each mock exec's the real module, patches ONLY the functions
   that touch the outside world *into the real module's namespace*, and
   re-exports everything (see `_mockutil.py` for why patching the real
   namespace matters). What gets mocked:
   - `bitcoin_info` — fake `AuthServiceProxy` (bitcoind RPC) backed by
     `fixtures/bitcoin.json`; the real update/caching code runs unchanged.
   - `lightning_info` — `lnd_get`/`lnd_get_v2` return `fixtures/lightning.json`.
   - `electrum_info` — fake `requests` serving prometheus metrics.
   - `systemctl_info` — service states from `/tmp/mock_services/<name>`.
   - `device_info` — uptime/serial/temp + simulated reboot/upgrade.
   - `application_info` — install/uninstall simulations (marker files only).
   - `pam` — login accepts `DEV_PASSWORD`.
   - `price_info`, `thread_functions`, `drive_info`, `transmissionrpc`.

2. **Fixture filesystem (`seed_fixture_fs.py`)** — the real code reads inline
   absolute paths (`/mnt/hdd/...`, `/home/bitcoin/.mynode/...`,
   `/usr/share/mynode/...`, `/tmp/...`), so the container recreates a
   provisioned device's filesystem. `/mnt/hdd` is a tmpfs *mount* because the
   code greps `/proc/mounts` for it.

3. **Fake binaries (`fake_bin/`)** — installed into `/usr/bin` in the
   container (many calls use absolute paths). `systemctl` reads/writes the
   same `/tmp/mock_services` files as the python mock; `journalctl` emits
   canned logs; `mynode_*.sh` scripts are no-ops or tiny simulations.

`dev_server.py` imports the real `app` from `mynode.py`, seeds the in-memory
data caches, registers the `/dev` blueprint + overlay injector, and runs Flask
in debug mode. A light 30s refresher keeps mocked values jittering; set
`DEV_REAL_THREADS=1` to run the app's real background threads instead.

## Customizing sample data

Edit the JSON files in `fixtures/` (block height, peers, channels, balances,
invoices, prices, service states, device identity) — they reload on next
refresh without restarting the container. Default-installed apps are listed in
`seed_fixture_fs.py` (`DEFAULT_INSTALLED_APPS`).

## Known quirks

- Port **8888** (not 8000) because the repo's release file server uses 8000.
- The QuickSync download page shows "Waiting on download client to start..."
  (no transmission daemon; the stub raises, which the real page handles).
- `/dev/*` endpoints are unauthenticated; the container binds to 127.0.0.1 only.
