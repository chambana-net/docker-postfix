docker-postfix
==============
Configurable Docker container for Chambana.net's SMTP setup.

Usage
-----
This container runs Postfix and Mailman (using uwsgi). It is designed to be run as part of a complex of multiple containers, including [`chambana/dovecot`](https://github.com/chambana-net/docker-dovecot), [`chambana/amavis`](https://github.com/chambana-net/docker-amavis), an LDAP server container (by default FreeIPA via [`adelton/freeipa-server`](https://github.com/adelton/docker-freeipa)), and an auto-configuring nginx proxy with LetsEncrypt certificate support as provided by [`jwilder/nginx-proxy`](https://github.com/jwilder/nginx-proxy) and [`jrcs/letsencrypt-nginx-proxy-companion`](https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion).

These environment variables are available for configuring Postfix. They correspond to the equivalent configuration options in the [Postfix documentation](http://www.postfix.org/postconf.5.html):
* `POSTFIX_MAILNAME`: 
* `POSTFIX_PROXY_INTERFACES`
* `POSTFIX_MYHOSTNAME`
* `POSTFIX_MYDESTINATION`
* `POSTFIX_MYNETWORKS`
* `POSTFIX_VIRTUAL_ALIAS_DOMAINS`
* `POSTFIX_VIRTUAL_MAILBOX_DOMAINS`
* `POSTFIX_RELAY_DOMAINS`

These environment variables allow you to configure the hostname and port for the Dovecot server used for SASL authentication:
* `POSTFIX_SASL_HOST`
* `POSTFIX_SASL_PORT`

These environment variables allow you to configure the hostname and port for the Dovecot server used for delivery:
* `POSTFIX_DELIVERY_HOST`
* `POSTFIX_DELIVERY_PORT`

These environment variables allow you to configure the hostname and port for the Amavis server used for pre-queue spam filtering:
* `POSTFIX_SPAM_HOST`
* `POSTFIX_SPAM_PORT`

These environment variables correspond to the available options in a [Postfix ldap_table](http://www.postfix.org/ldap_table.5.html) lookup for `virtual_mailbox_maps` and `smtpd_sender_login_maps`:
* `POSTFIX_LDAP_SERVER_HOST`
* `POSTFIX_LDAP_SEARCH_BASE`
* `POSTFIX_LDAP_BIND_DN`
* `POSTFIX_LDAP_BIND_PW`

This variable holds the domain used for Mailman lists, used for configuring both the Postfix transport map and Mailman itself:
* `MAILMAN_DOMAIN`

These environment variables correspond to the available options in mm_cfg.py, including the optional Spamassassin filtering module:
* `MAILMAN_DEFAULT_SERVER_LANGUAGE`
* `MAILMAN_SPAMASSASSIN_HOLD_SCORE`
* `MAILMAN_SPAMASSASSIN_DISCARD_SCORE`
* `MAILMAN_LISTMASTER`

This variable is the site-wide Mailman administrative password.
* `MAILMAN_SITEPASS`

A sample `docker-compose.yml` stanza holding the complete configuration for an example system:
```
  nginx:
    image: nginx:1.9
    container_name: nginx
    restart: on-failure:5
    network_mode: bridge
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/nginx/conf.d
      - /etc/nginx/vhost.d
      - /usr/share/nginx/html
      - /etc/letsencrypt/live:/etc/nginx/certs:ro

  docker-gen:
    image: jwilder/docker-gen
    container_name: docker-gen
    restart: on-failure:5
    network_mode: bridge
    volumes_from:
      - nginx
    volumes:
      - /etc/docker-gen/templates/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro
      - /var/run/docker.sock:/tmp/docker.sock:ro
    entrypoint: /usr/local/bin/docker-gen -notify-sighup nginx -watch -only-exposed -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf

  letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    container_name: letsencrypt
    restart: on-failure:5
    network_mode: bridge
    volumes_from:
      - nginx
    volumes:
      - /etc/letsencrypt/live:/etc/nginx/certs:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - NGINX_DOCKER_GEN_CONTAINER=docker-gen

  freeipa:
    image: adelton/freeipa-server
    container_name: freeipa
    hostname: ipa.example.com
    restart: on-failure:5
    network_mode: bridge
    ports:
      - "53:53"
      - "53:53/udp"
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
      - freeipa:/data
    environment:
      - IPA_SERVER_IP=192.0.2.2
      - PASSWORD=foobar
      - IPA_SERVER_INSTALL_OPTS=--no-forwarders
      - VIRTUAL_HOST=ipa.example.com
      - VIRTUAL_PROTO=https
      - VIRTUAL_PORT=443
      - LETSENCRYPT_HOST=ipa.example.com
      - LETSENCRYPT_EMAIL=hostmaster@example.com

  postfix:
    image: chambana/postfix
    container_name: postfix
    hostname: smtp.example.com
    restart: on-failure:5
    network_mode: bridge
    ports:
      - "25:25"
      - "587:587"
    volumes:
      - /etc/letsencrypt/live/smtp.example.com:/etc/letsencrypt:ro
      - lists:/var/lib/mailman
    environment:
      - VIRTUAL_HOST=smtp.example.com,lists.example.com
      - LETSENCRYPT_HOST=smtp.example.com,lists.example.com
      - LETSENCRYPT_EMAIL=hostmaster@example.com
      - POSTFIX_MAILNAME=smtp.example.com
      - POSTFIX_PROXY_INTERFACES=192.0.2.1
      - POSTFIX_MYHOSTNAME=smtp.example.com
      - POSTFIX_MYDESTINATION=localhost
      - POSTFIX_MYNETWORKS=127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 172.16.0.0/12
      - POSTFIX_VIRTUAL_ALIAS_DOMAINS=
      - POSTFIX_VIRTUAL_MAILBOX_DOMAINS=example.com
      - POSTFIX_RELAY_DOMAINS=lists.example.com
      - MAILMAN_DOMAIN=lists.example.com
      - MAILMAN_LISTMASTER=postmaster@example.com
      - MAILMAN_SITEPASS=foobar
      - POSTFIX_LDAP_SERVER_HOST=ldap
      - POSTFIX_LDAP_SEARCH_BASE=cn=users,cn=accounts,dc=example,dc=com
      - POSTFIX_LDAP_BIND_DN=uid=admin,cn=users,cn=accounts,dc=example,dc=com
      - POSTFIX_LDAP_BIND_PW=foobar
    links:
      - freeipa:ldap
      - dovecot:dovecot
      - amavis:amavis

  dovecot:
    image: chambana/dovecot
    container_name: dovecot
    hostname: imap.example.com
    restart: on-failure:5
    network_mode: bridge
    ports:
      - "143:143"
    volumes:
      - /etc/letsencrypt/live/imap.example.com:/etc/letsencrypt:ro
      - /etc/dovecot/ssl-parameters.dat:/var/lib/dovecot/ssl-parameters.dat
      - mailboxes:/var/mail
    environment:
      - VIRTUAL_HOST=imap.example.com
      - LETSENCRYPT_HOST=imap.example.com
      - LETSENCRYPT_EMAIL=hostmaster@example.com
      - DOVECOT_LDAP_URIS=ldap://ldap
      - DOVECOT_LDAP_BASE=dc=chambana,dc=net
      - DOVECOT_LDAP_AUTH_BIND_USERDN=uid=%n,cn=users,cn=accounts,dc=example,dc=com
    links:
      - freeipa:ldap

  amavis:
    image: chambana/amavis
    container_name: amavis
    hostname: spam.example.com
    restart: on-failure:5
    network_mode: bridge
    volumes:
      - spam_bayes:/var/lib/amavis/.spamassassin
    environment:
      - AMAVIS_MAILNAME=example.com
```
