# myNode System Notes

Various restrictions and behaviors of myNode and the various applications are documented below.

## General
- Not all applications can be enabled at once on most hardware. It will overload the system resources and cause unstable
behavior. If this happens, try disabling some applications. Some examples of this are:
  - Applications crashing, especially Bitcoin, and it will appear like blocks are lost and need to be re-synced
  - The Bitcoin log may show numerous "RPC Work Queue" errors
  - Electrum may stop syncing at a specific block until the device is rebooted.

## Device Specific Notes
- Raspberry Pi 4 users who are still using a 32-bit based Operating System may not see all new application versions. They are encouraged to upgrade to a 64-bit OS by downloading a new 64-bit image from mynodebtc.com/download. Known
differences are:
 - BTC Pay Server versions are locked to v1.3.x
 - grpcio is locked to v1.40.0 due to GLIBC compatibility
 - LNDg requires a custom grpcio version, may cause issues
 - Dojo is locked to v1.14.0
 - Mempool is locked to v2.3.1

## Data Drive Format
- Choosing btrfs as the data drive format is still beta and may have issues
 - btrfs may be slower than ext4
 - The swapfile will not work with btrfs

## Testnet Toggle
- Testnet can be enabled via the settings page. This is a great way to test various Bitcoin and Lightning applications. However, not all apps support testnet yet or have not been integrated within myNode to work on testnet. The following apps
have support or patial support.
 - Bitcoin
 - Lightning
 - Electrum Server
 - Ride the Lightning
 - THunderhub
 - Specter
 - Bitcoin RPC Explorer

## Lightning Terminal

- The Lightning Terminal password is randomized when it is installed. You can view it via the Lightning page.
- The password may be updated to your myNode password in future versions.

## Thunderhub

- When Thunderhub is first installed, logging in will be disabled. You must either change your password or log out and log back in of the the myNode UI before using Thunderhub. At that point, Thunderhub will use the same password as myNode.

## BTC Pay Server

- The upgrade button within BTC Pay Server will not work on myNode. Upgrades are performed as part of the myNode upgrade process.
- On 32-bit ARM devices BTC Pay Server can only upgrade to version 1.3.6

## CKBunker

- On some occasions, the CKBunker application will stop detecting a ColdCard that has been attached for a significant period of time.
  - Workaround: Run these commands as root.
    - echo 0 > /sys/bus/usb/devices/<coldcard device>/authorized
    - echo 1 > /sys/bus/usb/devices/<coldcard device>/authorized
- CKBunker uses a separate password that starts as "bolt" and can be updated within the app
- The password is stored in plaintext on the myNode drive

## Sphinx Relay

- Connection strings may only work a single time but are re-generated on each reboot. Since myNode does not know which string was used to successfully connect, they continue to be displayed in the UI, even though they may no longer be valid.

## Mempool

- Mempool can be resource intensive on some hardware. If the device runs slowly, try disabling some applications.

## Specter

- Specter authentication is off by default, but it will store and use its own password.
- It is highly recommended to enable authentication.

## LNDg

- The default credentials for LNDg are "admin" / "bolt"