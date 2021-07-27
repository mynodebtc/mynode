# Active Bounties

The myNode team is offering bounties for various improvements to improve the Bitcoin and Lightning experience for users. Working code should be submitted as a pull request via GitHub and must be merged to collect the bounty. To inquire about status of a bounty, to contribute to a bounty, or to propose a new bounty please email admin@mynodebtc.com.

## Migration Tool
Known active efforts: none

Payout: 1,000,000 sats (0.01 BTC)

With the growing number of node options available, some users would like to migrate more easily to myNode. I would be nice if the following user experience was possible, allowing migrate of critical data to a new myNode setup.

- Boot myNode with RaspiBlitz or Umbrel drive
- Prompt user to migrate drive
- If confirmed
  - Update the drive to use myNode drive folder format
  - Move Bitcoin data
  - Migrate Lightning data
  - Move old data to backup folder (optional, depends on size)
- Reboot

Alternatively, create two tools to more easily import data specifically for LND and Bitcoin.

For example, a tool to import a tarball of LND data + prompt for existing password to put in the .lndpw file. For bitcoin, possibly a page to prompt for a server + password to SCP files from or a way to upload a tarball.

## myNode Guides

Known active efforts: none

Payout: Various / guide

Additional myNode guides would be helpful for users attempting to use various tools or features.

- Guide for replacing each piece of hardware (100k sats)
- Guide to check seed via BlueWallet (100k sats)
- Guide to update specific app versions (100k sats)
- Guide for fsck error (75k sats)
- Guide for WiFi (100k sats)
- Open JoininBox / JoinMarket (75k sats)
- Blue wallet w/ tor (100k sats)
- Developer guide to add new application (150k sats)
- Guide walking user through Clone Tool usage (75k sats)
- Guide to setup BTCPay for public access via HTTPS with Custom Domain (150k sats)

GitHub: https://github.com/mynodebtc/mynodebtc.github.io

## Add BIP 158 Toggle 

Known active efforts: none

Payout: 200k sats

It may be beneficial to some users to enable block filters so addresses can be scanned faster. A toggle should be made available on the Bitcoin page to enable block filters (blockfilterindex=1). Changing this would probably need to reboot the node and the user should be prompted for confirmation prior to saving. The toggle should look similar to the watchtower toggle on the LND page.

This does take extra disk space the creating the it may take some time. The user should be appropriately warned of the tradeoffs.

## Add Page to Manage Lightning Watchtower

Known active efforts: none

Payout: 250k sats

Users that want to use watchtower will likely prefer more detailed information available via the myNode UI. Watchtower integration is currently limited to enabling and disabling watchtower functionality along with viewing the watchtower URI.

The watchtower config for tor is already setup and should be ready to use.

Acceptance Criteria:
- New link on Lightning page going to watchtower-specific page
- New watchtower page
  - View watchtower clients, status, and details (lncli wtclient [towers, tower, stats, policy, ...])
  - Add new tower (lncli wtclient add ...)
  - Remove tower (lncli wtclient remove ...)
- Should work if testnet is enabled

Helpful links:

https://github.com/lightningnetwork/lnd/blob/master/docs/watchtower.md

https://github.com/openoms/lightning-node-management/blob/master/advanced-tools/watchtower.md

## Add WARden Terminal Application

Known active efforts: none

Payout: 250k sats

Warden Terminal is a very interesting application that users would like to see available on myNode.

Acceptance Criteria:
- Warden Terminal application installed similar to existing applications
- Warden Terminal icon visible on the home screen
- Warden Terminal page in the UI that explains how to open the application in the Linux Terminal (similar to JoininBox)
- Verify install, re-install, uninstall options work on application page for Warden Terminal
- New `mynode-warden-terminal` command available in Linux Terminal to easily open application (similar to `mynode-joininbox`)

Helpful links:

https://github.com/pxsocs/warden_terminal

# Claimed Bounties

## myNode Guides

Additional myNode guides would be helpful for users attempting to use various tools or features.

- ~~Guide for voltage error (75k sats)~~
- ~~SD card read only error (75k sats)~~