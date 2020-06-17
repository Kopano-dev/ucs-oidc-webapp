#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

err_report() {
    echo "An error occurded on line $1 of this script."
}

trap 'err_report $LINENO' ERR

if [ ! "$(id -u)" -eq 0 ]; then
	echo "This script needs to be run as root or through sudo"
	exit 1
fi

# switch to dir of script in case its executed from somewhere else
cd "$(dirname "$(readlink -f "$0")")"

ucr unset \
	kopano/webapp/config/OIDC_ISS \
	kopano/webapp/config/OIDC_CLIENT_ID \
	kopano/cfg/server/kcoidc_issuer_identifier \
	kopano/cfg/server/enable_sso \
	kopano/cfg/server/kcoidc_initialize_timeout

systemctl restart kopano-server
