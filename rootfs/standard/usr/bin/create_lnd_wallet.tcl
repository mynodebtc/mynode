#!/usr/bin/expect

set timeout 5

set f [open "/mnt/hdd/mynode/settings/.lndpw"]
set pw [read $f]
set seed [lindex $argv 0];
close $f

set tls_cert "/home/bitcoin/.lnd/tls.cert" 
set macaroon "/home/bitcoin/.lnd/data/chain/mainnet/admin.macaroon"

spawn lncli --tlscertpath $tls_cert --macaroonpath $macaroon create
expect {
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
        "want to use? (Enter y/n):" {
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