# myNode System Notes

Various restrictions and behaviors of myNode and the various applications are documented below.

## General
- Not all applications can be enabled at once on most hardware. It will overload the system resources and cause unstable
behavior. If this happens, try disabling some applications. Some examples of this are:
  - Applications crashing, especially Bitcoin, and it will appear like blocks are lost and need to be re-synced
  - The Bitcoin log may show numerous "RPC Work Queue" errors
  - Electrum may stop syncing at a specific block until the device is rebooted.

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

## Thunderhub

- When Thunderhub is first installed, logging in will be disabled. You must either change your password or log out and log back in of the the myNode UI before using Thunderhub. At that point, Thunderhub will use the same password as myNode.

## BTC Pay Server

- The upgrade button within BTC Pay Server will not work on myNode. Upgrades are performed as part of the myNode upgrade process.

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
