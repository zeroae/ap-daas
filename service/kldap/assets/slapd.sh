#!/bin/sh

ulimit -n 1024
export KRB5_KTNAME=/etc/ldap/sasl2/krb5.keytab
slapd -h "ldap:// ldapi://" -u openldap -g openldap $@
