# myNode System Notes

Various restrictions and behaviors of myNode and the various applications are documented below.

## Thunderhub

- When Thunderhub is first installed, logging in will be disabled. You must either change your password or log out and log back in of the the myNode UI before using Thunderhub. At that point, Thunderhub will use the same password as myNode.

## BTC Pay Server

- The upgrade button within BTC Pay Server will not work on myNode. Upgrades are performed as part of the myNode upgrade process.

## CKBunker

- On some occasions, the CKBunker application will stop detecting a ColdCard that has been attached for a significant period of time.
-- Workaround: Run these commands as root.
    echo 0 > /sys/bus/usb/devices/<coldcard device>/authorized
    echo 1 > /sys/bus/usb/devices/<coldcard device>/authorized
- CKBunker uses a separate password that starts as "bolt" and can be updated within the app
- The password is stored in plaintext on the myNode drive

## Sphinx Relay

- Connection strings may only work a single time but are re-generated on each reboot. Since myNode does not know which string was used to successfully connect, they continue to be displayed in the UI, even though they may no longer be valid.