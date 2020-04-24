#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

err_report() {
    echo "An error occurded on line $1 of this script."
}

trap 'err_report $LINENO' ERR

random_string() {
    LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c32
}

if [ ! "$(id -u)" -eq 0 ]; then
	echo "This script needs to be run as root or through sudo"
	exit 1
fi

# install git to make the version lookup succeed
dpkg -s git 2>/dev/null >/dev/null || univention-install git

if [ "$(ucr get appcenter/apps/owncloud/status)" != "installed" ]; then
    echo "ownCloud is not installed"
    exit 1
fi

eval "$(ucr shell)"

source .env

# remove oidc registration so that it can be readded with potentially a new fqdn
# will print a "E: object not found" to the log if entry is not there
udm oidc/rpservice remove "$@" --dn cn=owncloud,cn=oidc,cn=univention,"$(ucr get ldap/base)" || true

echo "adding oidc registration"
# ucs will take care of restarting the app
udm oidc/rpservice create "$@" --ignore_exists \
    --set name=owncloud \
    --position=cn=oidc,cn=univention,"$(ucr get ldap/base)" \
    --set clientid=owncloud \
    --set clientsecret=owncloud \
    --set trusted=yes \
    --set applicationtype=web \
    --set redirectURI="https://$FQDN_KONNECT/owncloud/index.php/apps/openidconnect/redirect"

echo "Please go to https://$FQDN_KONNECT/owncloud to log into ownCloud via oidc."
