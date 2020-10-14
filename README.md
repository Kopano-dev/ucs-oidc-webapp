# Configuration helper for OIDC login for Kopano WebApp

This project will configure Kopano WebApp so that it will use OpenID Connect (OIDC) for logging in. This means that once a user has logged into WebApp he can seamlessly use other applications that are configured to use the OIDC Provider of Univention (like for example [Kopano Meet](https://www.univention.com/products/univention-app-center/app-catalog/kopano-meet/)).

## Requirements

To checkout the project `git` needs to be installed on the system. Further more the script makes the assumption that the "[Kopano Core](https://www.univention.com/products/univention-app-center/app-catalog/kopano-core/)", "[Kopano WebApp](https://www.univention.com/products/univention-app-center/app-catalog/kopano-webapp/)" (needs to be at least version 3.5.14.2539) and "[OpenID Connect Provider](https://www.univention.com/products/univention-app-center/app-catalog/openid-connect-provider/)" apps are installed on the same system.

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

To configure your Kopano Core and the Kopano WebApp app for login via OpenID Connect just execute `./run.sh` once. Running the script will take care of configuring the OpenID Connect Provider App, create a helper user in Kopano to let Konnect establish a permenent session, configure the Univention webserver and make the neccesary config changes.

Running the script will also create a file called `.env` in the current directory. In this file all installation specific variables are stored. In case the FQDN should be changed, or the OpenID Connect Provider app is available under a different domain just change these values here and rerun the script.

Running the script should only take a few moments. After it has completed it will print the URL from which you can reach Kopano WebApp.

## Things you should know

- The OpenID Connect flow is sensitive to the domain name its called with. `FQDN_KONNECT` should reflect both the domain that Konnect and WebApp are reachable under.
- In case your system is not reachable through the default domains just specify any differing values during the run of the script
  - Please refer to the documentation of the OpenID Provider app on changing its domain
- When enabling OIDC login for WebApp the old login mechanism is no longer available.
- When configuring OIDC login for kopano-server then kopano-server needs to resolve the OIDC discovery document at startup (which means Konnect must already be running).
- `/etc/ssl` is mounted into the Konnect container, so all ssl certificates trusted by the host are also trusted by Konnect.

## How to do this all manually

This section is meant to give an overview of how the components in this script connect with each other, so that this setup can be replicated in setups distributed over multiple servers (and in mixed UCS/Non-UCS environments).

### Why does it need a second instance of Kopano Konnect?

The Konnect that is part of the [OpenID Provider app](https://www.univention.com/products/univention-app-center/app-catalog/openid-connect-provider/) is configured to use the LDAP backend to look up users. But to be able to log in to `kopano-server` the OIDC token needs a reference to the internal Kopano user id. The easiest way to achieve this is to start another Konnect instance (this time directly using `kopano-server` as the user backend) and configuring this second Konnect to use the Univention provided one as its "authority".

### What kind of configuration needs to be applied to the second Konnect?

The second Konnect should be installed on the same system that is already running `kopano-server`. In a Kopano Multiserver environment it could be installed on multiple nodes, but can also be installed only on a single server.

In case Konnect is installed multiple times the `signing_private_key` and `encryption_secret_key` need to be identical on all systems and these system should all be reachable from the same domain name.

Normally Konnect is using the credentials provided by the user at login to establish an authenticated connection to `kopano-server` (required to look up user details), but when using an external authority this is no longer possible and therefore Konnect needs to be supplied with login credentials of its own. We recommend to create a dedicated user for this in Kopano, the user only needs normal user privileges and can be hidden from the GAB.

The user can be configured in Konnect by adding `KOPANO_SERVER_USERNAME` and `KOPANO_SERVER_PASSWORD` to `konnectd.cfg`.

In case `kopano-server` is installed on a UCS system with the "master" or "backup" role Konnect also needs to be configure to use a different base path for its web part. This can be done with the option `uri_base_path` (as of 0.33.8 this config option is not handled in the packaging of Konnect. [Change to packaging](https://stash.kopano.io/projects/KC/repos/konnect/pull-requests/157/overview)).

Lastly Konnect needs to be reachable from the outside. An example for Apache with a differing base can be fund inside the [`run.sh` script](https://github.com/Kopano-dev/ucs-oidc-webapp/blob/9b5b83ef56975ade46c0a60b863826edd303f7df/run.sh#L99-L103). Check [the Kopano documentation](https://documentation.kopano.io/kopanocore_administrator_manual/configure_kc_components.html#configure-a-webserver-for-konnect) for other webservers.

Once the above parts are in place `kopano-server` needs to be configured to use our new Konnect instance. This can be done by running the following command (or doing the change manually in `server.cfg` if `kopano-server` is not running on UCS):

```bash
ucr set \
    kopano/cfg/server/kcoidc_issuer_identifier="https://ucs-1234.kopano.intranet/kopanoid" \
    kopano/cfg/server/enable_sso=yes
```

`kcoidc_issuer_identifier` needs to reflect the domain name Konnect is reachable at.

### What kind of configuration needs to be applied to the OpenID Connect Provider?

On the UCS side our second Konnect only needs to be registered as a client. This can be achieved by running:

```bash
udm oidc/rpservice create "$@" --ignore_exists \
    --set name=kopano-core \
    --position=cn=oidc,cn=univention,"$(ucr get ldap/base)" \
    --set clientid=kopano-webapp \
    --set clientsecret="a-generated-secret" \
    --set trusted=yes \
    --set applicationtype=web \
    --set redirectURI="https:/ucs-1234.kopano.intranet/kopanoid/signin/v1/identifier/oauth2/cb"
```

In the above command the value for `clientsecret` and `redirectURI` need to be adapted to your environment.

Once Konnect is registered at the OpenID Connect provider we need to add the following to the `identifier registration` of our second Konnect:

```yaml
authorities:
- name: ucs-konnect
  default: true
  iss: https://ucs-sso.kopano.intranet
  client_id: kopano-webapp
  client_secret: a-generated-secret
  authority_type: oidc
  response_type: id_token
  scopes:
  - openid
  - profile
  - email
  trusted: true
  end_session_enabled: true
```

Here the same client secret needs to be used as during the client registration and `iss` needs to be the domain of the Univention OpenID Connect Provider.

### Where does WebApp point to?

As a last step Kopano WebApp needs to be configured to use our second Konnect as its ID provider. In case Kopano WebApp and Kopano server are served on the same domain nothing further needs to be configured. In case WebApp is served under a different domain name it needs to be registered as a client with our second Konnect. The steps for this are explained in the [WebApp admin documentation](https://documentation.kopano.io/webapp_admin_manual/config.html#single-sign-on-oidc) and the [Kopano admin documentation](https://documentation.kopano.io/kopanocore_administrator_manual/configure_kc_components.html#configure-3rd-party-applications-to-authenticate-using-konnect).
