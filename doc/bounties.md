# Active Bounties

The myNode team is offering bounties for various improvements to improve the Bitcoin and Lightning experience for users. Working code should be submitted as a pull request via GitHub and must be merged to collect the bounty. To inquire about status of a bounty, to contribute to a bounty, or to propose a new bounty please email admin@mynodebtc.com.

## Migration Tool
Known active efforts: none

Payout: 1,000,000 sats (0.01 BTC)

With the growing number of node options available, some users would like to migrate more easily to myNode. I would be nice if the following user experience was possible, allowing migrate of critical data to a new myNode setup.

- Boot myNode with RaspiBlitz or Umbrel drive
- Prompt user to migrate drive
- If confirmed
-- Update the drive to use myNode drive folder format
-- Move Bitcoin data
-- Migrate Lightning data
-- Move old data to backup folder (optional, depends on size)
- Reboot

Alternatively, create two tools to more easily import data specifically for LND and Bitcoin.

For example, a tool to import a tarball of LND data + prompt for existing password to put in the .lndpw file. For bitcoin, possibly a page to prompt for a server + password to SCP files from or a way to upload a tarball.

## myNode Guides

Known active efforts: none

Payout: Various / guide

Additional myNode guides would be helpful for users attempting to use various tools or features.

- Guide for replacing each piece of hardware (100k sats)
- Guide to Enable / disable Tor (50k sats)
- Guide to check seed via BlueWallet (50k sats)
- Guide to update specific app versions (75k sats)
- Guide for voltage error (50k sats)
- Guide for fsck error (50k sats)
- Guide for WiFi (100k sats)
- Open JoininBox / JoinMarket (75k sats)
- SD card read only error (50k sats)
- Blue wallet w/ tor (75k sats)
- Developer guide to add new application (100k sats)
- Guide to setup BTCPay for public access via HTTPS with Custom Domain (100k sats)

GitHub: https://github.com/mynodebtc/mynodebtc.github.io

## Add BIP 158 Toggle 

Known active efforts: none

Payout: 200k sats

It may be beneficial to some users to enable block filters so addresses can be scanned faster. A toggle should be made available on the Bitcoin page to enable block filters (blockfilterindex=1). Changing this would probably need to reboot the node and the user should be prompted for confirmation prior to saving. The toggle should look similar to the watchtower toggle on the LND page.

This does take extra disk space the creating the it may take some time. The user should be appropriately warned of the tradeoffs.

## Add Page to Manage Lightning Watchtower

Known active efforts: none

Payout: 200k sats

TODO: Add details

## Add WARden Terminal Application

Known active efforts: none

Payout: 200k sats

TODO: Add details

# Claimed Bounties

None yet!