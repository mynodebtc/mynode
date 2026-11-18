# Security policy

## Reporting a vulnerability

Please **do not open a public issue or pull request** for a security problem.
MyNode devices hold Bitcoin and Lightning funds, so a public report can put users at
risk before a fix ships.

Report it privately through GitHub instead:
**Security** tab → **Report a vulnerability**
(https://github.com/mynodebtc/mynode/security/advisories/new).

If you can't use GitHub, email **admin@mynodebtc.com**.

Please include:

- The MyNode version and device (e.g. Model Two, Raspberry Pi, PC/VM)
- Steps to reproduce
- What an attacker needs (local network access, a logged-in session, physical
  access, ...) and what they can get

We'll reply to confirm we've received it and keep you updated while we work on a fix.
We're happy to credit you in the advisory and release notes if you'd like.

## Supported versions

Fixes go into the latest MyNode release. Users get them by upgrading from the device's
web interface or the Linux terminal.

## Scope

In scope: the MyNode software in this repository, including the web interface, the
setup and upgrade scripts, and how MyNode installs and configures bundled apps.

If apps included on MyNode are out of date and have a vulnerability, please report
those and the application can be updated to include the fix.

Out of scope here:

- **New bugs in upstream apps** bundled with MyNode (Bitcoin Core, LND, Electrs, and so on)
  that aren't caused by MyNode's configuration: report those to the upstream project so it 
  can be fixed at the source.
  If you aren't sure, report here and we'll route it.
- **The documentation site**: report it on
  [mynodebtc/mynode_docs](https://github.com/mynodebtc/mynode_docs/security/advisories/new)
- **www.mynodebtc.com**: email admin@mynodebtc.com
- Findings that come only from an automated scanner, and denial-of-service

## Please don't

- Test against devices, nodes, or accounts that aren't yours
- Include private keys, seed phrases, macaroons, or wallet files in a report. We will
  never ask for them.
