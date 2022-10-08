#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "That script must be run as root"
	exit 1
fi

# Fetch system release variables
source /etc/os-release

function get_release {
	DIST=$ID
	case $ID in
		debian|ubuntu|raspbian)
			if [[ -n $DEBIAN_CODENAME ]]; then
				VERSION_CODENAME=$DEBIAN_CODENAME
			fi

			if [[ -n $UBUNTU_CODENAME ]]; then
				VERSION_CODENAME=$UBUNTU_CODENAME
			fi

			if [[ -z $VERSION_CODENAME ]]; then
				echo "Couldn't find VERSION_CODENAME in your /etc/os-release file. Did your system supported? Please report issue to me by writing to email: 'r4sas <at> i2pd.xyz'"
				exit 1
			fi
			RELEASE=$VERSION_CODENAME
		;;
		*)
			if [[ -z $ID_LIKE || "$ID_LIKE" != "debian" && "$ID_LIKE" != "ubuntu" ]]; then
				echo "Your system is not supported by this script. Currently it supports debian-like and ubuntu-like systems."
				exit 1
			else
				DIST=$ID_LIKE
				case $ID_LIKE in
					debian)
						if [[ "$ID" == "kali" ]]; then
							if [[ "$VERSION" == "2019"* || "$VERSION" == "2020"* ]]; then
								RELEASE="buster"
							elif [[ "$VERSION" == "2021"* || "$VERSION" == "2022"* ]]; then
								RELEASE="bullseye"
							fi
						else
							RELEASE=$DEBIAN_CODENAME
						fi
					;;
					ubuntu)
						RELEASE=$UBUNTU_CODENAME
					;;
				esac
			fi
		;;
	esac
	if [[ -z $RELEASE ]]; then
		echo "Couldn't detect your system release. Please report issue to me by writing to email: 'r4sas <at> i2pd.xyz'"
		exit 1
	fi
}

get_release

echo "Importing signing key"
wget -q -O - https://repo.i2pd.xyz/r4sas.gpg | apt-key --keyring /etc/apt/trusted.gpg.d/i2pd.gpg add -

echo "Adding APT repository"
echo "deb https://repo.i2pd.xyz/$DIST $RELEASE main" > /etc/apt/sources.list.d/i2pd.list
echo "deb-src https://repo.i2pd.xyz/$DIST $RELEASE main" >> /etc/apt/sources.list.d/i2pd.list
