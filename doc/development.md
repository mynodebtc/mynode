# Developing for MyNode

## Loading Modified Software
Once you are running MyNode, you can easily modify and update the software yourself!

1. Start by running MyNode on your device via the instructions above in "Running MyNode"
2. Modify MyNode files
    * Clone this git repo on your PC or laptop - `git clone https://github.com/mynodebtc/mynode.git`
    * Make your modifications
3. Run `make rootfs`
    * Or run `make rootfs_auto` in a new console tab
    * This will automatically create artifacts as local files are modified
4. Copy the artifact to your device, either over HTTP or with scp (see below)
5. Test your changes!
6. Submit Pull Request to share your updates!

To create a new MyNode application, see the [application guide](applications.md).

### Option 1 - Download over HTTP
Best when repeatedly updating a device, since only the last step is repeated for each build.

1. Run `make start_file_server`
    * This will run a local HTTP server so your device can download files
2. On your device, run `sudo mynode-local-upgrade [dev pc ip address]`
    * This will download your locally generated artifact and install it on your device
    * Your device will automatically reboot to ensure updates take effect

### Option 2 - Copy with scp
Best for a one-off update, or when the device cannot reach your PC over HTTP.

1. On your PC, copy the artifact to the device (the device type must match your device)

    ```
    scp out/mynode_rootfs_[device type].tar.gz admin@[device ip]:/tmp/
    ```

2. On your device, run `sudo mynode-local-upgrade /tmp/mynode_rootfs_[device type].tar.gz`
    * This installs the copied artifact directly, downloading nothing
    * Your device will automatically reboot to ensure updates take effect


### To update a subsystem without rebooting
Add another argument to the local upgrade script. This works with either option above, so the first argument is your dev PC IP address or the path to a copied artifact.
- To update files only, run `sudo mynode-local-upgrade [ip address or file] files`
- To update files and restart web server, run `sudo mynode-local-upgrade [ip address or file] www`
- To update files and reload applications, run `sudo mynode-local-upgrade [ip address or file] apps`
