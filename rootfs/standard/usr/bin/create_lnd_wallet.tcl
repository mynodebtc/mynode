#!/usr/bin/expect

set timeout 5

set f [open "/mnt/hdd/mynode/settings/.lndpw"]
set pw [read $f]
close $f

set seed [lindex $argv 0];
set backup_args ""
if { [file exists "/tmp/lnd_channel_backup"] == 1} {      
    set backup_args "--multi_file=/tmp/lnd_channel_backup"
}

set tls_cert "/home/bitcoin/.lnd/tls.cert" 
set macaroon "/home/bitcoin/.lnd/data/chain/mainnet/admin.macaroon"
set network "--network=mainnet"
if { [file exists "/mnt/hdd/mynode/settings/.testnet_enabled"] == 1} {
    set macaroon "/home/bitcoin/.lnd/data/chain/testnet/admin.macaroon"
    set network "--network=testnet"
}

spawn lncli $network --tlscertpath $tls_cert --macaroonpath $macaroon create $backup_args
expect {
        "recover funds from a static channel backup? (Enter y/n):" {
                send -- "y\n"
                exp_continue
        }
        "Input wallet password:" {
                send -- "$pw\n"
        }
        timeout { exit 2 }
}
expect {
        "password:" {
                send -- "$pw\n"
        }
        timeout { exit 2 }
}
expect {
        "create a new seed (Enter y/x/n):" {
                send -- "y\n"
        }
        timeout { exit 2 }
}
expect {
        "spaces:" {
                send -- "$seed\n"
        }
        timeout { exit 2 }
}
expect {
        "passphrase):" {
                send -- "\n"
        }
        timeout { exit 2 }
}
expect {
        "0):" {
                send -- "\n"
        }
        timeout { exit 2 }
}
expect eof

lassign [wait] pid spawnid os_error_flag return_code

exit $return_code