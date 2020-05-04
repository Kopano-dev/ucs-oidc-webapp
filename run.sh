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

DOCKERIZE_VERSION=0.11.0

if ! command -v dockerize > /dev/null; then
    curl -sfL "https://github.com/powerman/dockerize/releases/download/v$DOCKERIZE_VERSION/dockerize-$(uname -s)-$(uname -m)" \
    | install /dev/stdin /usr/local/bin/dockerize
    dockerize --version
fi

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
	value_default="$hostname.$domainname"
	read -r -p "FQDN where kopano-server is running [$value_default]: " new_value
	FQDN_KONNECT=${new_value:-$value_default}

	value_default="$(ucr get ucs/server/sso/fqdn)"
	read -r -p "FQDN where the openid connect provider is running [$value_default]: " new_value
	FQDN_SSO=${new_value:-$value_default}

	cat <<-EOF >"./.env"
INSECURE=false
FQDN_KONNECT=$FQDN_KONNECT
FQDN_SSO=$FQDN_SSO
clientsecret=$(random_string)
OIDCLOGIN=$(random_string)
EOF
fi

source .env

echo "Creating helper user to establish a global session for Konnect"
# required for external auth provider usage
udm users/user create "$@" --ignore_exists \
    --position cn=kopano,"$ldap_base" \
    --set username="oidc-helper" \
    --set description="Kopano OpenID Connect Helper" \
    --set password="$OIDCLOGIN" \
    --set lastname="OIDC Helper" \
    --set mailPrimaryAddress="oidc@$(ucr get domainname)" \
    --set kopano-role=user \
    --set kopano-user-hidden=1

# remove oidc registration so that it can be readded with potentially a new fqdn
# will print a "E: object not found" to the log if entry is not there
udm oidc/rpservice remove "$@" --dn cn=kopano-core,cn=oidc,cn=univention,"$(ucr get ldap/base)" || true

echo "adding oidc registration"
# ucs will take care of restarting the app
udm oidc/rpservice create "$@" --ignore_exists \
    --set name=kopano-core \
    --position=cn=oidc,cn=univention,"$(ucr get ldap/base)" \
    --set clientid=kopano-webapp \
    --set clientsecret="$clientsecret" \
    --set trusted=yes \
    --set applicationtype=web \
    --set redirectURI="https://$FQDN_KONNECT/kopanoid/signin/v1/identifier/oauth2/cb"

echo "configuring Apache"
cat << EOF >/etc/apache2/ucs-sites.conf.d/kopano-konnect.conf
ProxyPass /kopanoid/.well-known/openid-configuration http://127.0.0.1:38777/.well-known/openid-configuration retry=0
ProxyPass /kopanoid/ http://127.0.0.1:38777/kopanoid/ retry=0
EOF

cat << EOF >/etc/apache2/ucs-sites.conf.d/kopano-webapp.conf
RewriteCond %{REQUEST_URI} ^/webapp$ [OR]
RewriteCond %{REQUEST_URI} ^/webapp/
RewriteCond %{HTTP_HOST} !^$FQDN_KONNECT$ [NC]
RewriteRule ^(.*)$ https://$FQDN_KONNECT/webapp/ [R,L]
EOF

invoke-rc.d apache2 reload

# Fix quoting in config.php so that the listener can properly update it
cp /etc/kopano/webapp/config.php{,-bak}
tr "'" '"' </etc/kopano/webapp/config.php >/etc/kopano/webapp/config.php-quotes
mv /etc/kopano/webapp/config.php-quotes /etc/kopano/webapp/config.php

echo "setting config options in WebApp and kopano-core for oidc"
ucr set \
    kopano/webapp/config/LANG?'"en_US"' \
    kopano/webapp/config/OIDC_ISS="\"https://$FQDN_KONNECT/kopanoid/"\" \
    kopano/webapp/config/OIDC_CLIENT_ID='"Kopano-WebApp"' \
    kopano/cfg/server/kcoidc_issuer_identifier="https://$FQDN_KONNECT/kopanoid" \
    kopano/cfg/server/enable_sso=yes \
    kopano/cfg/server/kcoidc_initialize_timeout?360

# run the following to undo:
# ucr unset kopano/webapp/config/OIDC_ISS kopano/webapp/config/OIDC_CLIENT_ID kopano/cfg/server/kcoidc_issuer_identifier kopano/cfg/server/enable_sso && systemctl restart kopano-server
echo "pulling containers before starting"
docker-compose pull

echo "starting containers"
docker-compose up -d

echo "restarting kopano-server to apply changes"
systemctl restart kopano-server

echo "Waiting for kopano-server to startup, then syncing user list to create the new user"
dockerize \
        -wait tcp://127.0.0.1:236 \
        -timeout 120s \
	kopano-admin --sync

echo "Please go to https://$FQDN_KONNECT/webapp to log into Kopano WebApp via oidc."
