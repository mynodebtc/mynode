# Developing for MyNode

## Loading Modified Software
Once you are running MyNode, you can easily modify and update the software yourself!

1. Start by running MyNode on your device via the instructions above in "Running MyNode"
2. Modify MyNode files
    * Clone this git repo on your PC or laptop - `git clone https://github.com/mynodebtc/mynode.git`
    * Make your modifications
3. Build and install the artifact on your device (see the options below)
4. Test your changes!
5. Submit Pull Request to share your updates!

To create a new MyNode application, see the [application guide](applications.md).

### Option 1 - Push from your PC (recommended)
`scripts/push-local-upgrade.sh` does the whole build-copy-install cycle from your PC, with nothing to type on the device.

```
scripts/push-local-upgrade.sh [device ip] [service]
```

It connects over SSH, detects the device type, rebuilds the rootfs for just that type, copies the artifact with scp, and runs `mynode-local-upgrade` on the device. The optional service argument is the same one described in "To update a subsystem without rebooting" below; with no service argument the device reboots.

```
scripts/push-local-upgrade.sh 192.168.1.50 www     # rebuild, install, restart web server
scripts/push-local-upgrade.sh 192.168.1.50         # rebuild, install, full upgrade + reboot
```

Options:

| Option | Effect |
|--------|--------|
| `-u, --user USER` | SSH user on the device (default `admin`) |
| `-n, --no-build` | Skip the rebuild and push the existing artifact in `out/` |
| `-t, --type TYPE` | Skip detection and use this device type |
| `-k, --keep` | Leave the copied artifact on the device |

### Option 2 - Download over HTTP
Best when repeatedly updating a device, since only the last step is repeated for each build.

1. Run `make rootfs`
    * Or run `make rootfs_auto` in a new console tab, which rebuilds as local files are modified
    * To build for a single device type, run `make rootfs DEVICES="[device type]"`
2. Run `make start_file_server`
    * This will run a local HTTP server so your device can download files
3. On your device, run `sudo mynode-local-upgrade [dev pc ip address]`
    * This will download your locally generated artifact and install it on your device
    * Your device will automatically reboot to ensure updates take effect

### Option 3 - Copy with scp
Best for a one-off update, or when the device cannot reach your PC over HTTP.

1. On your PC, run `make rootfs`, then copy the artifact to the device (the device type must match your device)

    ```
    scp out/mynode_rootfs_[device type].tar.gz admin@[device ip]:/tmp/
    ```

2. On your device, run `sudo mynode-local-upgrade /tmp/mynode_rootfs_[device type].tar.gz`
    * This installs the copied artifact directly, downloading nothing
    * Your device will automatically reboot to ensure updates take effect


### To update a subsystem without rebooting
Add another argument to the local upgrade script. This works with any of the options above. For `push-local-upgrade.sh` it is the second argument; for `mynode-local-upgrade` it follows the dev PC IP address or the path to a copied artifact.
- To update files only, run `sudo mynode-local-upgrade [ip address or file] files`
- To update files and restart web server, run `sudo mynode-local-upgrade [ip address or file] www`
- To update files and reload applications, run `sudo mynode-local-upgrade [ip address or file] apps`
