# Welcome to WARden implementation of MyNode

This is a light weight version of the original WARden designed for integration with a MyNode running Specter Wallet.

Transactions will be imported automatically from wallets at Specter server.

This app was built with a couple of goals:
. Easily track portfolio values in fiat (private requests through Tor)
. Monitor Wallets and Addresses for activity using your own node

# Installation

If you are not using a monitor and keyboard at your MyNode, remote connect from your laptop / desktop:

```bash
ssh admin@<local ip>
```

Run the following commands to install for the first time. Your local ip address can be found at your MyNode settings.

```bash
ssh admin@<local ip>
cd /var/www/mynode
sudo wget https://raw.githubusercontent.com/pxsocs/warden_mynode/production/warden_upgrade.sh
source ./warden_install.sh -install-icon
```

## This is an Open Source project

We believe Open Source is the future of development for bitcoin. There is no other way when transparency and privacy are critical.

Thanks for supporting a future where software is built with these ideals. All proceeds go towards improving the app.

### We suggest a one time payment of 200,000sats

But it's completely up to you the amount and if you want to contribute.

# First Run

The MyNode version of the WARden feeds from wallet activity from Specter Server. Make sure you import at least one wallet with transaction activities at Specter and it should automatically show at WARden.

Bitcoin fiat prices are assumed to be the ones at transaction date. A future release will allow for editing.

# Sats for Features

As interest for the app grows and if the community contributes, new features will be added like:
. Import of other transactions
. Editing of transactions
. Enhanced statistics - volatility, compare performance, heatmaps, ...
. Specter implementation without MyNode
. Email notifications
. And suggested improvements

But the app is also open source so anyone can contribute. Anyone looking to contribute / get a bounty is welcome.

## Privacy

Most portfolio tracking tools ask for personal information and may track your IP and other information. My experience is that even those who say they don't, may have log files at their systems that do track your IP and could be easily linked to your data.

### Why NAV is important?

NAV is particularly important to anyone #stackingsats since it tracks performance relative to current capital allocated.
For example, a portfolio going from $100 to $200 may seem like it 2x but the performance really depends if any new capital was invested or divested during this period. **NAV adjusts for cash inflows and outflows.**

## NAV Tracking

NAV tracks performance based on amount of capital allocated. For example, a portfolio starts at $100.00 on day 0. On day 1, there is a capital inflow of an additional $50.00. Now, if on day 2, the Portfolio value is $200, it's easy to conclude that there's a $50.00 profit. But in terms of % appreciation, there are different ways to calculate performance.
CB Calculates a daily NAV (starting at 100 on day zero).
In this example:

| Day | Portfolio Value\* | Cash Flow  | NAV | Performance |
| --- | ----------------- | ---------- | --- | ----------- |
| 0   | \$0.00            | + \$100.00 | 100 | --          |
| 1   | \$110.00          | + \$50.00  | 110 | +10.00% (1) |
| 2   | \$200.00          | None       | 125 | +25.00% (2) |

> - Portfolio Market Value at beginning of day
>   (1) 10% = 110 / 100 - 1
>   (2) 25% = 200 / (110 + 50) - 1

Tracking NAV is particularly helpful when #stackingsats. It calculates performance based on capital invested at any given time. A portfolio starting at $100 and ending at $200 at a given time frame, at first sight, may seem like is +100% but that depends entirely on amount of capital invested
along that time frame.

**Please note that this is ALPHA software. There is no guarantee that the
information and analytics are correct. Also expect no customer support. Issues are encouraged to be raised through GitHub but they will be answered on a best efforts basis.**
