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

if [ "$(ucr get appcenter/apps/kopano-core/status)" != "installed" ]; then
    echo "Kopano Core is not installed"
    exit 1
fi

if [ "$(ucr get appcenter/apps/kopano-webapp/status)" != "installed" ]; then
    echo "Kopano WebApp is not installed"
    exit 1
fi

if [ "$(ucr get appcenter/apps/openid-connect-provider/status)" != "installed" ]; then
    echo "OpenID Connect Provider is not installed"
    exit 1
fi

eval "$(ucr shell)"

if [ ! -e ./.env ]; then
	cat <<-EOF >"./.env"
INSECURE=false
FQDN_KONNECT=$hostname.$domainname
FQDN_SSO=$(ucr get ucs/server/sso/fqdn)
clientsecret=$(random_string)
OIDCLOGIN=$(random_string)
EOF
fi

source .env

# Create helper user to establish a global session for Konnect (required for external auth provider usage)
udm users/user create "$@" --ignore_exists \
    --position "cn=kopano,"$ldap_base"" \
    --set "username"="oidc-helper" \
    --set "description"="Kopano OpenID Connect Helper" \
    --set "password"="$OIDCLOGIN" \
    --set "lastname"="OIDC Helper" \
    --set mailPrimaryAddress="oidc@$(ucr get domainname)" \
	--set kopano-role=user \
    --set kopano-user-hidden=1

# Sync user list to create the new user
kopano-admin --sync

# remove oidc registration so that it can be readded with potentially a new fqdn
# will print a "E: object not found" to the log if entry is not there
udm oidc/rpservice remove "$@" --dn cn=kopano-core,cn=oidc,cn=univention,"$(ucr get ldap/base)" || true

# add oidc registration. ucs will take care of restarting the app
udm oidc/rpservice create "$@" --ignore_exists \
 --set name=kopano-core \
 --position=cn=oidc,cn=univention,"$(ucr get ldap/base)" \
 --set clientid=kopano-webapp \
 --set clientsecret="$clientsecret" \
 --set trusted=yes \
 --set applicationtype=web \
 --set redirectURI="https://$FQDN_KONNECT/kopanoid/signin/v1/identifier/oauth2/cb"

# apache2 conf
cat << EOF >/etc/apache2/ucs-sites.conf.d/kopano-konnect.conf
ProxyPass /kopanoid/.well-known/openid-configuration http://127.0.0.1:38777/.well-known/openid-configuration retry=0
ProxyPass /kopanoid/ http://127.0.0.1:38777/kopanoid/ retry=0
EOF

invoke-rc.d apache2 reload

# Fix quoting in config.php so that the listener can properly update it
cp /etc/kopano/webapp/config.php{,-bak}
tr "'" '"' </etc/kopano/webapp/config.php >/etc/kopano/webapp/config.php-quotes
mv /etc/kopano/webapp/config.php-quotes /etc/kopano/webapp/config.php

# Set config options in WebApp and kopano-core for oidc
ucr set \
	kopano/webapp/config/LANG?'"en_US"' \
	kopano/webapp/config/OIDC_ISS="\"https://$FQDN_KONNECT/kopanoid/"\" \
	kopano/webapp/config/OIDC_CLIENT_ID='"Kopano-WebApp"' \
	kopano/cfg/server/kcoidc_issuer_identifier="https://$FQDN_KONNECT/kopanoid/" \
	kopano/cfg/server/enable_sso=yes \
	kopano/cfg/server/kcoidc_initialize_timeout?360

# run the following to undo:
# ucr unset kopano/webapp/config/OIDC_ISS kopano/webapp/config/OIDC_CLIENT_ID kopano/cfg/server/kcoidc_issuer_identifier kopano/cfg/server/enable_sso && systemctl restart kopano-server
# pull containers before starting
docker-compose pull

# restart kopano-server to apply changes
systemctl restart kopano-server

# start containers
docker-compose up -d

echo "Please go to https://$FQDN_KONNECT/webapp to log into Kopano WebApp via oidc."
