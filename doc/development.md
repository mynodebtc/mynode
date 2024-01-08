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
4. Run 'make start_file_server'
    * This will run a local HTTP server so your device can download files
5. On your device, run `sudo mynode-local-upgrade [dev pc ip address]`
    * This will download your locally generated artifact and install it on your device
    * Your device will automatically reboot to ensure updates take effect
6. Test your changes!
7. Submit Pull Request to share your updates!

### To update a subsystem without rebooting
Add another argument to the local upgrade script:
- To update files only, run `sudo mynode-local-upgrade [dev pc ip address] files`
- To update files and restart web server, run `sudo mynode-local-upgrade [dev pc ip address] www`


## Setup new device to run MyNode
This steps will setup a new device and can be used for making images. These steps allow for updates to the `setup_device.sh` script that does the initial install.

1. Run make command for your device. Ex:
    * `make setup_new_rock64`
    * `make setup_new_rockpro64`
    * `make setup_new_raspi3`
    * `make setup_new_raspi4`
    * `make setup_new_raspi5`
    * `make setup_new_debian`
    * `make setup_new_other`
3. Follow Instructions
2. Reboot Device
4. Congratulations! You're running a new MyNode device!