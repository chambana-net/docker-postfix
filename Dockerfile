FROM chambana/base:latest

MAINTAINER Josh King <jking@chambana.net>

RUN apt-get -qq update

RUN apt-get install -y --no-install-recommends micro-httpd \
                                               uwsgi \
                                               uwsgi-plugin-cgi \
                                               mailman \
                                               postfix \
                                               postfix-ldap \
                                               postfix-policyd-spf-python \
                                               supervisor

ENV MAILMAN_DEFAULT_SERVER_LANGUAGE en
ENV MAILMAN_SPAMASSASSIN_DISCARD_SCORE 8
ENV MAILMAN_SPAMASSASSIN_HOLD_SCORE 5

RUN mkdir -p /etc/postfix/ldap
ADD files/postfix/main.cf /etc/postfix/main.cf
ADD files/postfix/master.cf /etc/postfix/master.cf
ADD files/postfix/ldap/virtual.cf /etc/postfix/ldap/virtual.cf

ADD files/mailman/mm_cfg.py /etc/mailman/mm_cfg.py

ADD files/uwsgi/mailman.conf /etc/uwsgi/mailman.conf

ADD files/supervisor/supervisord.conf /etc/supervisor/supervisord.conf

EXPOSE 25 80 587

## Add startup script.
ADD bin/init.sh /opt/chambana/bin/init.sh
RUN chmod 0755 /opt/chambana/bin/init.sh

CMD ["/opt/chambana/bin/init.sh"]
