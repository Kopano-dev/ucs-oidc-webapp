The below is soon no longer neccesary as the owncloud app by default will use openid

## Configure OIDC login for ownCloud

Enable the oidc plugin in the ownCloud app:

```bash
univention-app shell ownloud occ app:enable openidconnect
```

Add the following block at the end of `/var/lib/univention-appcenter/apps/owncloud/conf/config.php`:

```php
  'openid-connect' => [
    'provider-url' => 'https://ucs-sso.kopano.intranet',
    'client-id' => 'owncloud',
    'client-secret' => 'owncloud',
    'loginButtonName' => 'OpenID Connect',
    'autoRedirectOnLoginPage' => false,
    'redirect-url' => 'https://ucs-1555.kopano.intranet/owncloud/index.php/apps/openidconnect/redirect',
    'mode' => 'email',
    'search-attribute' => 'email',
    'use-token-introspection-endpoint' => false
  ]
```

Run `./owncloud.sh` to add an entry for ownCloud to the openid-provider configuration registry.

