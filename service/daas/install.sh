#!/bin/bash -e
# this script is run during the image build

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -rf /var/lib/ldap /etc/ldap/slapd.d

log-helper info 'Converting Kerberos ldap schema to ldif.'
gunzip -c /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz > \
    /etc/ldap/schema/kerberos.schema
echo "include /etc/ldap/schema/kerberos.schema" > ~/kerberos_schema.conf
mkdir ~/ldif_result
slapcat -f ~/kerberos_schema.conf -F ~/ldif_result \
    -s "cn=kerberos,cn=schema,cn=config"
head --lines=-7 ~/ldif_result/cn\=config/cn\=schema/cn\=\{0\}kerberos.ldif |
    sed -e 's/{0}kerberos/kerberos,cn=schema,cn=config/' > /etc/ldap/schema/kerberos.ldif

chown openldap:openldap /etc/ldap/schema/kerberos.*

rm -rf ~/kerberos_schema.conf ~/ldif_result


exit 0
