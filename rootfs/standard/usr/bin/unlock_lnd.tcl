#!/usr/bin/expect

set timeout 20

set tls_cert "/home/bitcoin/.lnd/tls.cert" 
set macaroon "/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon"
set network "--network=mainnet"
if { [file exists "/mnt/hdd/mynode/settings/.testnet_enabled"] == 1} {
    set macaroon "/home/bitcoin/.lnd/data/chain/testnet/admin.macaroon"
    set network "--network=testnet"
}

set f [open "/mnt/hdd/mynode/settings/.lndpw"]
set pw [read $f]

spawn lncli $network --tlscertpath $tls_cert --macaroonpath $macaroon unlock
expect {
        "wallet password:" {
                send -- "$pw\n"
        }
}
expect {
        "Wallet is already unlocked" {
            exit 0
        }
        eof {
            lassign [wait] pid spawnid os_error_flag return_code
            exit $return_code
        }
}

exit 99