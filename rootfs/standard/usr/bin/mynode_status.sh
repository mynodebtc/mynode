#!/bin/bash

printStatus() {
	for app in $*; do
		STATUS=`systemctl status ${app} | grep Active | awk '{print $2}'`
		if [[ $STATUS == "active" ]]; then
			echo -e "$app: \e[32m $STATUS\e[0m"
		elif [[ $STATUS == "inactive" ]]; then
			echo -e "$app: \e[33m $STATUS\e[0m"
		fi
	done
}

echo ":::::::::Core-Services:::::"
printStatus bitcoind electrs lnd tor vpn | column -t

echo -e "\n:::::::Other-Services::::::"
printStatus btc_rpc_explorer btcpayserver dojo firewall https glances \
	    lndconnect lndhub quicksync netdata rtl webssh2 whirlpool www | column -t

echo -e "\n::::::::Beta-Services::::::"
printStatus caravan lnbits specter thunderhub | column -t
