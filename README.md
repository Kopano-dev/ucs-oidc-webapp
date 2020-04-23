# Configuration helper for OIDC login for Kopano WebApp

This project will configure Kopano WebApp so that it will use OpenID Connect (OIDC) for logging in. This means that once a user has logged into WebApp he can seamlessly use other applications that are configured to use the OIDC Provider of Univention (like for example Kopano Meet).

## Requirements

To checkout the project `git` needs to be installed on the system. Further more the script makes the assumption that the "Kopano Core", "Kopano WebApp" (needs to be at least version 3.5.14.2539) and "OpenID Connect Provider" apps are installed on the same system.

```bash
univention-install git
```

After `git` has been installed it needs to be cloned to the local disk by running the below command and afterwards switch into the newly created directory.

```bash
$ git clone https://github.com/Kopano-dev/ucs-oidc-webapp
$ cd ucs-oidc-webapp
$ ls
LICENSE.txt  README.md  docker-compose.yml  run.sh
```

## WebApp configuration notice

To ensure compatibility with the configuration listener of Kopano4UCS the script converts all quoting in WebApps `config.php` to double quotes. This procedure should be safe, but a backup of the old file is kept in case this causes any issues with the current installation. For new installations `config.php` will use double quotes by default [starting with Kopano WebApp 4.0](https://forum.kopano.io/topic/3070/webapp-config-php-double-quotes-consistency).

## Running the script

To configure your Kopano Core and the Kopano WebApp app for login via OpenID Connect just run the script once. Running the script will take care of configuring the OpenID Connect Provider App, create a helper user in Kopano to let Konnect establish a permenent session, configure the Univention webserver and make the neccesary config changes.

Running the script will also create a file called `.env` in the current directory. In this file all installation specific variables are stored. In case the FQDN should be changed, or the OpenID Connect Provider app is available under a different domain just change these values here and rerun the script.

Running the script should only take a few moments. After it has completed it will print the URL from which you can reach Kopano WebApp.

## Things you should know

- The OpenID Connect flow is sensitive to the domain name its called with. FQDN_KONNECT should reflect both the domain that Konnect and WebApp are reachable under.
- In case your system is not reachable through the default domains just specify any differing values during the run of the script
  - Please refer to the documentation of the OpenID Provider app on changing its domain
- When enabling OIDC login for WebApp the old login mechanism is no longer available.
- When configuring OIDC login for kopano-server then kopano-server needs to resolve the oidc discovery document at startup (which means Konnect must already be running).
- `/etc/ssl` is mounted into the Konnect container, so all ssl certificates trusted by the host are also trusted by Konnect.

## Known issues

- ~~Logging out of Kopano WebApp (and therefore the internal Konnect instance) will not log the user out of the Univention OpenID Provider~~ no longer the case with the Kopano Konnect >= 0.33.0
- When opening from an url other than $FQDN_KONNECT there will be redirection to the OpenID Provider. To circumvent this from happening every access from a different domain than the expected should be rewritten.
  - Example:
  ```
RewriteCond %{REQUEST_URI} ^/webapp$ [OR]
RewriteCond %{REQUEST_URI} ^/webapp/
RewriteCond %{HTTP_HOST} !^$FQDN_KONNECT$ [NC]
RewriteRule ^(.*)$ https://$FQDN_KONNECT/webapp/ [R,L]
```
  - add this to conf-enabled during script run?
