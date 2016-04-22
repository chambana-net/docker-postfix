#!/bin/bash -

. /opt/chambana/lib/common.sh

CHECK_BIN postconf
CHECK_BIN sed
CHECK_VAR POSTFIX_MAILNAME
CHECK_VAR POSTFIX_PROXY_INTERFACES
CHECK_VAR POSTFIX_MYHOSTNAME
CHECK_VAR POSTFIX_MYDESTINATION
CHECK_VAR POSTFIX_MYNETWORKS
CHECK_VAR POSTFIX_VIRTUAL_ALIAS_DOMAINS
CHECK_VAR POSTFIX_VIRTUAL_MAILBOX_DOMAINS
CHECK_VAR POSTFIX_RELAY_DOMAINS
CHECK_VAR POSTFIX_LDAP_SERVER_HOST
CHECK_VAR POSTFIX_LDAP_SEARCH_BASE
CHECK_VAR POSTFIX_LDAP_BIND_DN
CHECK_VAR POSTFIX_LDAP_BIND_PW
CHECK_VAR POSTFIX_SASL_HOST
CHECK_VAR POSTFIX_SASL_PORT
CHECK_VAR POSTFIX_DELIVERY_HOST
CHECK_VAR POSTFIX_DELIVERY_PORT
CHECK_VAR POSTFIX_SPAM_HOST
CHECK_VAR POSTFIX_SPAM_PORT
CHECK_VAR MAILMAN_DOMAIN
CHECK_VAR MAILMAN_DEFAULT_SERVER_LANGUAGE
CHECK_VAR MAILMAN_SPAMASSASSIN_HOLD_SCORE
CHECK_VAR MAILMAN_SPAMASSASSIN_DISCARD_SCORE
CHECK_VAR MAILMAN_LISTMASTER
CHECK_VAR MAILMAN_SITEPASS

MSG "Configuring system mailname..."

echo "$POSTFIX_MAILNAME" > /etc/mailname

MSG "Configuring Postfix main.cf..."

SASL_URI="lmtp:[$(getent hosts $POSTFIX_SASL_HOST | head -n1 | awk '{ print $1 }')]:$POSTFIX_SASL_PORT"
DELIVERY_URI="lmtp:[$(getent hosts $POSTFIX_DELIVERY_HOST | head -n1 | awk '{ print $1 }')]:$POSTFIX_DELIVERY_PORT"
SPAM_URI="amavis:[$(getent hosts $POSTFIX_SPAM_HOST | head -n1 | awk '{ print $1 }')]:$POSTFIX_SPAM_PORT"

postconf -e proxy_interfaces="$POSTFIX_PROXY_INTERFACES" \
	myhostname="$POSTFIX_MYHOSTNAME" \
	mydestination="$POSTFIX_MYDESTINATION" \
	mynetworks="$POSTFIX_MYNETWORKS" \
	virtual_alias_domains="$POSTFIX_VIRTUAL_ALIAS_DOMAINS" \
	virtual_mailbox_domains="$POSTFIX_VIRTUAL_MAILBOX_DOMAINS" \
	relay_domains="$POSTFIX_RELAY_DOMAINS" \
	smtpd_sasl_path="$SASL_URI" \
	virtual_transport="$DELIVERY_URI"

postconf -Pe smtpd/pass/content_filter="$SPAM_URI"

MSG "Configuring Postfix LDAP settings..."

sed -i -e "s/^server_host\ *=.*/server_host\ =\ ${POSTFIX_LDAP_SERVER_HOST}/" \
	-e "s/^search_base\ *=.*/search_base\ =\ ${POSTFIX_LDAP_SEARCH_BASE}/" \
	-e "s/^bind_dn\ *=.*/bind_dn\ =\ ${POSTFIX_LDAP_BIND_DN}/" \
	-e "s/^bind_pw\ *=.*/bind_pw\ =\ ${POSTFIX_LDAP_BIND_PW}/" \
	/etc/postfix/ldap/virtual.cf

MSG "Configuring Mailman..."

sed -i -e "s/^DEFAULT_EMAIL_HOST\ *=.*/DEFAULT_EMAIL_HOST\ =\ \'${MAILMAN_DOMAIN}\'/" \
	-e "s/^DEFAULT_URL_HOST\ *=.*/DEFAULT_URL_HOST\ =\ \'${MAILMAN_DOMAIN}\'/" \
	-e "s/^DEFAULT_SERVER_LANGUAGE\ *=.*/DEFAULT_SERVER_LANGUAGE\ =\ \'${MAILMAN_DEFAULT_SERVER_LANGUAGE}\'/" \
	-e "s/^SPAMASSASSIN_DISCARD_SCORE\ *=.*/SPAMASSASSIN_DISCARD_SCORE\ =\ \'${MAILMAN_SPAMASSASSIN_DISCARD_SCORE}\'/" \
	-e "s/^SPAMASSASSIN_HOLD_SCORE\ *=.*/SPAMASSASSIN_HOLD_SCORE\ =\ \'${MAILMAN_SPAMASSASSIN_HOLD_SCORE}\'/" \
	-e "s/^POSTFIX_STYLE_VIRTUAL_DOMAINS\ *=.*/POSTFIX_STYLE_VIRTUAL_DOMAINS\ =\ \[\'${MAILMAN_DOMAIN}\'\]/" \
	-e "s/^DEB_LISTMASTER\ *=.*/DEB_LISTMASTER\ =\ \'${MAILMAN_LISTMASTER}\'/" \
	/etc/mailman/mm_cfg.py

if [[ ! -d /var/lib/mailman/lists/mailman ]]; then
	MSG "Creating Mailman site list..."
	/usr/lib/mailman/bin/newlist -q mailman "${MAILMAN_LISTMASTER}" "${MAILMAN_SITEPASS}"
fi

if [[ ! -d /var/run/mailman/ ]]; then
	mkdir -p /var/run/mailman
  chown -R list:list /var/run/mailman
fi

touch /etc/postfix/transports
postmap /etc/postfix/transports

touch /etc/postfix/virtual-alias.cf
postmap /etc/postfix/virtual-alias.cf

MSG "Starting Postfix..."

supervisord -c /etc/supervisor/supervisord.conf 
