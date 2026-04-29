# Copilot instructions for MyNode

## Build and validation commands

- `make rootfs` is the main repository build. It creates `out/mynode_rootfs_<device>.tar.gz` for `raspi4`, `raspi5`, `debian`, and `rockpro64`.
- `make rootfs_auto` starts the local file server and rebuilds rootfs artifacts when `rootfs/` or `CHANGELOG` changes.
- `make start_file_server` / `make stop_file_server` serves `out/` on port `8000` so a device can download locally built tarballs.
- On a running MyNode device, `sudo mynode-local-upgrade <dev-pc-ip>` installs the matching tarball from that file server. Use `sudo mynode-local-upgrade <dev-pc-ip> files` for a file-only refresh or `sudo mynode-local-upgrade <dev-pc-ip> www` to refresh files and restart the web UI without a full reboot.
- `make setup_new_<device>` is the fresh-device/bootstrap path. Current Makefile targets are `rock64`, `rockpro64`, `rockpi4`, `raspi3`, `raspi4`, `raspi5`, and `debian`.
- No repository-wide lint target or automated test suite is defined here, so there is no single-test runner to point Copilot at. Validation in this repo is normally `make rootfs` plus targeted on-device smoke testing through `mynode-local-upgrade`.

## High-level architecture

- This repo builds filesystem overlays, not a conventional local app package. `make_rootfs.sh` assembles a device image payload by copying `rootfs/standard/` into `out/rootfs_<device>/`, then layering `rootfs/<device>/` on top, then tarring the result.
- `setup/setup_device.sh` is the first-install/bootstrap path. It detects the hardware, installs OS packages and signing keys, downloads the correct rootfs tarball, lays the overlay onto the device, and initializes users and shared scripts.
- Runtime startup is systemd-driven. `rootfs/standard/etc/systemd/system/mynode.service` runs `/usr/bin/mynode_startup.sh`, which mounts the data drive, prepares persistent directories under `/mnt/hdd/mynode`, adds `/var/pynode` to Python's import path, and blocks the rest of the stack until the drive is ready.
- The web UI lives in `rootfs/standard/var/www/mynode`. `mynode.py` creates the Flask app and registers the built-in blueprints, `www.service` launches it through `/usr/bin/mynode_www.sh`, and nginx uses the shared config in `rootfs/standard/usr/share/mynode/nginx.conf`.
- Shared backend logic lives in `rootfs/standard/var/pynode`. The Flask routes import heavily from these modules for device state, service control, app metadata, and shell helpers instead of duplicating that logic in the route files.
- Application metadata is split across two layers: built-in/legacy apps are declared in `rootfs/standard/usr/share/mynode/application_info.json`, while version pins and version-file locations live in `rootfs/standard/usr/share/mynode/mynode_app_versions.sh`.
- Dynamic apps live under `rootfs/standard/usr/share/mynode_apps/<short_name>/`. `application_info.py` loads each `<short_name>.json`, and `mynode-manage-apps init` installs that app's service file, icon, screenshots, optional nginx config, Flask blueprint/templates, and install/uninstall scripts into the live filesystem.

## Key conventions

- Put shared changes in `rootfs/standard/` unless they are truly hardware-specific. Device overlays in `rootfs/<device>/` are for per-device differences, and `raspi5` intentionally reuses the `raspi4` overlay during rootfs builds.
- Do not treat the repo as the source of runtime state. Installed/enabled/version state is often derived from marker files under `/home/bitcoin/.mynode/` and `/mnt/hdd/mynode/settings/`, so UI or status changes often need matching changes to marker-file or service logic.
- When changing app wiring, keep all of the metadata layers aligned: built-in apps need `application_info.json` and often `mynode_app_versions.sh`; dynamic apps need `<app>.json` and usually matching `.service`, `scripts/`, `nginx/`, and `www/` assets under `usr/share/mynode_apps/<app>/`.
- Prefer metadata flags over hardcoded UI logic. Existing app definitions rely on fields like `supported_archs`, `minimum_debian_version`, `requires_bitcoin`, `requires_lightning`, `requires_electrs`, `supports_testnet`, and the homepage/status visibility flags.
- Keep Flask page modules thin when possible. The existing pattern is to put reusable system/app logic in `var/pynode` and let the `var/www/mynode` blueprints focus on routing and template rendering.
