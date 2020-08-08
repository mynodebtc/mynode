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

echo ":::::::::Core-Apps:::::"
printStatus bitcoind electrs lnd tor vpn | column -t

echo -e "\n:::::::Other-Apps::::::"
printStatus btc_rpc_explorer btcpayserver dojo firewall https glances \
	    lndconnect lndhub mempoolspace netdata quicksync rtl webssh2 whirlpool www | column -t

echo -e "\n::::::::Beta-Apps::::::"
printStatus caravan lnbits specter thunderhub | column -t

echo -e "\n::Background-Services::"
printStatus bandwidth check_in corsproxy_btcrpc docker_images drive_check \
			invalid_block_check lnd_admin_files lnd_backup lnd_unlock loopd \
			mynode rotate_logs tls_proxy torrent_check usb_driver_check | column -t
