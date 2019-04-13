#!/bin/bash -

. /app/lib/common.sh

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
CHECK_VAR POSTFIX_LDAP_START_TLS
CHECK_VAR POSTFIX_LDAP_SEARCH_BASE
CHECK_VAR POSTFIX_LDAP_BIND_DN
CHECK_VAR POSTFIX_LDAP_BIND_PW
CHECK_VAR POSTFIX_SASL_HOST
CHECK_VAR POSTFIX_SASL_PORT
CHECK_VAR POSTFIX_DELIVERY_HOST
CHECK_VAR POSTFIX_DELIVERY_PORT
CHECK_VAR POSTFIX_SPAM_HOST
CHECK_VAR POSTFIX_SPAM_PORT

MSG "Configuring system mailname..."

echo "$POSTFIX_MAILNAME" > /etc/mailname

MSG "Configuring Postfix main.cf..."

SASL_URI="inet:$POSTFIX_SASL_HOST:$POSTFIX_SASL_PORT"
DELIVERY_URI="lmtp:$POSTFIX_DELIVERY_HOST:$POSTFIX_DELIVERY_PORT"
SPAM_URI="scan:[$POSTFIX_SPAM_HOST]:$POSTFIX_SPAM_PORT"
: ${POSTFIX_RELAY_RECIPIENT_MAPS:=""}
: ${POSTFIX_RELAYHOST:="None"}
: ${OPENDKIM_NAMESERVERS:="9.9.9.9,1.1.1.1"}
MILTERS=""

if [[ "$MAILMAN_ENABLE" == "true" ]]; then
	POSTFIX_RELAY_RECIPIENT_MAPS="$POSTFIX_RELAY_RECIPIENT_MAPS hash:/var/lib/mailman/data/virtual-mailman"
fi

postconf -e proxy_interfaces="$POSTFIX_PROXY_INTERFACES" \
	myhostname="$POSTFIX_MYHOSTNAME" \
	mydestination="$POSTFIX_MYDESTINATION" \
	mynetworks="$POSTFIX_MYNETWORKS" \
	virtual_alias_domains="$POSTFIX_VIRTUAL_ALIAS_DOMAINS" \
	virtual_mailbox_domains="$POSTFIX_VIRTUAL_MAILBOX_DOMAINS" \
	relay_domains="$POSTFIX_RELAY_DOMAINS" \
	relay_recipient_maps="$POSTFIX_RELAY_RECIPIENT_MAPS" \
	smtpd_sasl_path="$SASL_URI" \
	virtual_transport="$DELIVERY_URI"

if [[ "$POSTFIX_RELAYHOST" != "None" ]]; then
postconf -e relayhost="[$POSTFIX_RELAYHOST]"
fi
	
if [[ "$OPENDKIM_ENABLE" == "true" ]]; then
	MILTERS="unix:/var/run/opendkim/opendkim.sock"
	sed -i -e "s/^Nameservers\ .*/Nameservers\ ${OPENDKIM_NAMESERVERS}/" \
		/etc/opendkim.conf
fi

if [[ "$OPENDMARC_ENABLE" == "true" ]]; then
	MILTERS="$MILTERS unix:/var/run/opendmarc/opendmarc.sock"
fi

if [[ "$OPENDKIM_ENABLE" == "true" || "$OPENDMARC_ENABLE" == "true" ]]; then
	postconf -e milter_default_action=accept \
		milter_protocol=6 \
		smtpd_milters="$MILTERS" \
		non_smtpd_milters="$MILTERS"
fi


postconf -Pe smtpd/pass/content_filter="$SPAM_URI"

MSG "Configuring Postfix LDAP settings..."

sed -i -e "s/^server_host\ *=.*/server_host\ =\ ${POSTFIX_LDAP_SERVER_HOST}/" \
	-e "s/^start_tls\ *=.*/start_tls\ =\ ${POSTFIX_LDAP_START_TLS}/" \
	-e "s/^search_base\ *=.*/search_base\ =\ ${POSTFIX_LDAP_SEARCH_BASE}/" \
	-e "s/^bind_dn\ *=.*/bind_dn\ =\ ${POSTFIX_LDAP_BIND_DN}/" \
	-e "s/^bind_pw\ *=.*/bind_pw\ =\ ${POSTFIX_LDAP_BIND_PW}/" \
	/etc/postfix/ldap/virtual.cf

if [[ ! -e /etc/postfix/transports ]]; then
	if [[ "$MAILMAN_ENABLE" == "true" ]]; then
		echo "${MAILMAN_DOMAIN} mailman:" > /etc/postfix/transports
	else
		touch /etc/postfix/transports
	fi
fi

if [[ ! -e /etc/postfix/virtual-sender.cf ]]; then
	touch /etc/postfix/virtual-sender.cf
fi

if [[ ! -e /etc/postfix/virtual-alias.cf ]]; then
	touch /etc/postfix/virtual-alias.cf
fi

postmap /etc/postfix/transports
postmap /etc/postfix/virtual-sender.cf
postmap /etc/postfix/virtual-alias.cf

MSG "Populating Postfix chroot..."
cp -a /etc/localtime /etc/hosts /etc/services /etc/resolv.conf /etc/nsswitch.conf /etc/host.conf /etc/passwd /var/spool/postfix/etc/
#cp -a /usr/lib/x86_64-linux-gnu/libnss_*.so* /var/spool/postfix/lib/
#cp -a /usr/lib/x86_64-linux-gnu/libresolv.so* /var/spool/postfix/lib/
#cp -a /usr/lib/x86_64-linux-gnu/libdb-*.so* /var/spool/postfix/lib/

cat > /etc/supervisor/supervisord.conf << EOF
[supervisord]
nodaemon=true
autostart=true
autorestart=true

[program:postfix]
command=/usr/sbin/postfix start
process_name=master
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:rsyslogd]
command=/usr/sbin/rsyslogd -n
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

if [[ "$MAILMAN_ENABLE" == "true" ]]; then
	CHECK_VAR MAILMAN_DOMAIN
	CHECK_VAR MAILMAN_DEFAULT_SERVER_LANGUAGE
	CHECK_VAR MAILMAN_SPAMASSASSIN_HOLD_SCORE
	CHECK_VAR MAILMAN_SPAMASSASSIN_DISCARD_SCORE
	CHECK_VAR MAILMAN_LISTMASTER
	CHECK_VAR MAILMAN_SITEPASS

	MSG "Configuring Mailman..."

	sed -i -e "s/^DEFAULT_EMAIL_HOST\ *=.*/DEFAULT_EMAIL_HOST\ =\ \'${MAILMAN_DOMAIN}\'/" \
		-e "s/^DEFAULT_URL_HOST\ *=.*/DEFAULT_URL_HOST\ =\ \'${MAILMAN_DOMAIN}\'/" \
		-e "s/^DEFAULT_SERVER_LANGUAGE\ *=.*/DEFAULT_SERVER_LANGUAGE\ =\ \'${MAILMAN_DEFAULT_SERVER_LANGUAGE}\'/" \
		-e "s/^SPAMASSASSIN_DISCARD_SCORE\ *=.*/SPAMASSASSIN_DISCARD_SCORE\ =\ \'${MAILMAN_SPAMASSASSIN_DISCARD_SCORE}\'/" \
		-e "s/^SPAMASSASSIN_HOLD_SCORE\ *=.*/SPAMASSASSIN_HOLD_SCORE\ =\ \'${MAILMAN_SPAMASSASSIN_HOLD_SCORE}\'/" \
		-e "s/^POSTFIX_STYLE_VIRTUAL_DOMAINS\ *=.*/POSTFIX_STYLE_VIRTUAL_DOMAINS\ =\ \[\'${MAILMAN_DOMAIN}\'\]/" \
		-e "s/^DEB_LISTMASTER\ *=.*/DEB_LISTMASTER\ =\ \'${MAILMAN_LISTMASTER}\'/" \
		/etc/mailman/mm_cfg.py

	MSG "Setting Mailman sitepass..."
	/usr/sbin/mmsitepass "${MAILMAN_SITEPASS}"

	if [[ ! -d /var/lib/mailman/lists/mailman ]]; then
		MSG "Creating Mailman site list..."
		/usr/lib/mailman/bin/newlist -q mailman "${MAILMAN_LISTMASTER}" "${MAILMAN_SITEPASS}"
	fi

	if [[ ! -d /var/run/mailman/ ]]; then
		mkdir -p /var/run/mailman
		chown -R list:list /var/run/mailman
	fi

cat >> /etc/supervisor/supervisord.conf << EOF

[program:mailman]
command=/usr/lib/mailman/bin/mailmanctl -s start
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:uwsgi]
command=/usr/bin/uwsgi --ini /etc/uwsgi/mailman.ini
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

fi

if [[ "$OPENDKIM_ENABLE" == "true" ]]; then
cat >> /etc/supervisor/supervisord.conf << EOF

[program:opendkim]
command=/usr/sbin/opendkim -x /etc/opendkim.conf
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

fi

if [[ "$OPENDMARC_ENABLE" == "true" ]]; then
cat >> /etc/supervisor/supervisord.conf << EOF

[program:opendmarc]
command=/usr/sbin/opendmarc -c /etc/opendmarc.conf -u opendmarc -p /var/run/opendmarc/opendmarc.sock
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

fi

MSG "Updating CA certificates..."
if [[ "$(ls -A /usr/local/share/ca-certificates)" ]]; then
	update-ca-certificates
fi

MSG "Starting Postfix..."

exec "$@"
