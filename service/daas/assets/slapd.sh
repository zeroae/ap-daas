#!/bin/sh

ulimit -n 1024
export KRB5_KTNAME=/etc/ldap/sasl2/krb5.keytab
[ -d /var/run/slapd ] || mkdir -p /var/run/slapd && chown -R openldap:openldap /var/run/slapd
slapd -h "ldap:// ldapi://" -u openldap -g openldap $@
