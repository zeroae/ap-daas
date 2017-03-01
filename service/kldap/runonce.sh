#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

log-helper level eq trace && set -x

function slapd_get_admin_password() {
    if [ -z "$LDAP_ADMIN_PASSWORD" ]; then
        log-helper info "Generating LDAP Admin Password..."
        LDAP_ADMIN_PASSWORD=$(cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 7)
        log-helper info "Generated LDAP Admin Password: $LDAP_ADMIN_PASSWORD"
    fi
}

function slapd_get_domain() {
    if [ -z "$LDAP_DOMAIN" ]; then
        LDAP_DOMAIN=$CONSUL_DOMAIN
        log-helper info "Setting LDAP_DOMAIN=$LDAP_DOMAIN"
    fi
}

function slapd_get_base_dn() {
    slapd_get_domain
    if [ -z "$LDAP_BASE_DN" ]; then
        IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
        for i in "${LDAP_BASE_DN_TABLE[@]}"; do
            EXT="dc=$i,"
            LDAP_BASE_DN=$LDAP_BASE_DN$EXT
        done
        LDAP_BASE_DN=${LDAP_BASE_DN::${#LDAP_BASE_DN}-1}
        log-helper info "Setting LDAP_BASE_DN=$LDAP_BASE_DN"
    fi
}

function slapd_start() {
    log-helper info "Start OpenLDAP..."
    slapd.sh -h "ldapi:///" -u openldap -g openldap

    log-helper info "Waiting for OpenLDAP to start..."
    while [ ! -e /run/slapd/slapd.pid ]; do sleep 0.1; done
    log-helper info "OpenLDAP Started."
}

function slapd_stop() {
    log-helper info "Stop OpenLDAP..."
    SLAPD_PID=$(cat /run/slapd/slapd.pid)
    kill -15 $SLAPD_PID
    log-helper info "Waiting for OpenLDAP to stop..."
    while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done
    log-helper info "OpenLDAP Stopped"
}

function slapd_add_schemas(){
    ldapadd -QY EXTERNAL -H ldapi:/// -f /etc/ldap/schema/kerberos.ldif
}

function slapd_apply_ldifs() {
    BASE_DIR=$1
    for f in $(find $BASE_DIR -mindepth 1 -maxdepth 1 -type f -name \*.ldif | sort); do
        log-helper info "Processing file ${f}"
        cat $f | envsubst > /tmp/$(basename $f)
        cat $f | envsubst \
            | ldapmodify -QY EXTERNAL -H ldapi:/// 2>&1 | log-helper debug \
            || cat $f | envsubst \
                | ldapmodify -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD -H ldapi:/// 2>&1 | log-helper debug
    done
}

function slapd_configure() {
    log-helper info "Configuring OpenLDAP..."

    [ -d /var/lib/ldap ] || mkdir -p /var/lib/ldap
    [ -d /etc/ldap/slapd.d ] || mkdir -p /etc/ldap/slapd.d

    chown -R openldap:openldap /var/lib/ldap
    chown -R openldap:openldap /etc/ldap
    chown -R openldap:openldap /var/lib/ldap

    slapd_get_domain
    slapd_get_base_dn

    if [ -z "$(ls -A -I lost+found /var/lib/ldap)" ] \
        && [ ! -z "$(ls -A -I lost+found /etc/ldap/slapd.d)" ]; then
        log-helper error "Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)"
        exit 1
    elif [ ! -z "$(ls -A -I lost+found /var/lib/ldap)" ] \
        && [ -z "$(ls -A -I lost+found /etc/ldap/slapd.d)" ]; then
        log-helper error "Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)"
        exit 1
    elif [ -z "$(ls -A -I lost+found /var/lib/ldap)" ] \
        && [ -z "$(ls -A -I lost+found /etc/ldap/slapd.d)" ]; then
        log-helper info "Database and config directory are empty..."
        log-helper info "Init new ldap server..."

        cat <<EOF | debconf-set-selections
slapd slapd/no_configuration boolean false
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANIZATION}
slapd slapd/backend string MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/dump_database select when needed
EOF
        dpkg-reconfigure -f noninteractive slapd

    fi
    log-helper info 'OpenLDAP configuration finished'
}

function slapd_kerberize(){
    log-helper info 'Kerberizing OpenLDAP'

    kadmin.local -q "addprinc -randkey ldap/$(hostname)"
    kadmin.local -q "ktadd -k /etc/ldap/sasl2/krb5.keytab ldap/$(hostname)"
    chown openldap:openldap /etc/ldap/sasl2/krb5.keytab

    cat <<EOF > /etc/ldap/ldap.conf
BASE    $LDAP_BASE_DN
URI     ldap://ldap.service.$CONSUL_DOMAIN
SASL_MECH   GSSAPI
EOF

    slapd_apply_ldifs $DIR/ldif.d/kerberized
}


function krb5_get_realm(){
    if [ -z "$KRB5_REALM" ]; then
        slapd_get_domain
        KRB5_REALM=${LDAP_DOMAIN^^}
    fi
}

function krb5_get_admsrv_password(){
    if [ -z "$KRB5_ADMSRV_PASSWORD" ]; then
        log-helper info "Generating Kerberos Admin Server Password"
        KRB5_ADMSRV_PASSWORD=$(cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 7)
        log-helper info "Generated Kerberos Admin Server Password: $KRB5_ADMSRV_PASSWORD"
    fi
}

function krb5_get_kdcsrv_password(){
    if [ -z "$KRB5_KDCSRV_PASSWORD" ]; then
        log-helper info "Generating Kerberos KDC Password"
        KRB5_KDCSRV_PASSWORD=$(cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 7)
        log-helper info "Generated Kerberos KDC Password: $KRB5_KDCSRV_PASSWORD"
    fi
}

function krb5_get_master_password(){
    if [ -z "$KRB5_MASTER_PASSWORD" ]; then
        log-helper info "Generating Kerberos Master Password"
        KRB5_MASTER_PASSWORD=$(cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 14)
        log-helper info "Generated Kerberos Master Password: $KRB5_MASTER_PASSWORD"
    fi
}

function krb5_create_realm(){
    log-helper info 'Adding Realm Subtree'

    kdb5_ldap_util="kdb5_ldap_util -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD -H ldapi:///"
    log-helper info 'Creating Realm Database'
    $kdb5_ldap_util create -P $KRB5_MASTER_PASSWORD -r $KRB5_REALM -s

    cat <<EOF | ldapadd -xD cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD -H ldapi:///
dn: cn=kdc-srv,cn=krb5,$LDAP_BASE_DN
cn: kdc-srv
objectClass: simpleSecurityObject
objectClass: organizationalRole
description: Default bind DN for the Kerberos KDC Server
userPassword: $KRB5_KDCSRV_PASSWORD

dn: cn=adm-srv,cn=krb5,$LDAP_BASE_DN
cn: adm-srv
objectClass: simpleSecurityObject
objectClass: organizationalRole
description: Default bind DN for the Kerberos Administration server
userPassword: $KRB5_ADMSRV_PASSWORD
EOF

    log-helper info 'Stashing SRV Passwords'
    cat <<EOF | $kdb5_ldap_util stashsrvpw -f /etc/krb5kdc/service.keyfile cn=kdc-srv,cn=krb5,$LDAP_BASE_DN
$KRB5_KDCSRV_PASSWORD
$KRB5_KDCSRV_PASSWORD
EOF
    cat <<EOF | $kdb5_ldap_util stashsrvpw -f /etc/krb5kdc/service.keyfile cn=adm-srv,cn=krb5,$LDAP_BASE_DN
$KRB5_ADMSRV_PASSWORD
$KRB5_ADMSRV_PASSWORD
EOF
}

function krb5_create_admin(){
    log-helper info 'Creating Kerberos Admin user'
    kadmin.local -q "addprinc -pw $KRB5_ADMIN_PASSWORD admin"
}

function krb5_configure(){
    log-helper info 'Configuring Kerberos 5'

    krb5_get_realm

    log-helper info "Admin authorization"
    echo "*/admin@$KRB5_REALM *" > /etc/krb5kdc/kadm5.acl
    echo "admin@$KRB5_REALM *" >> /etc/krb5kdc/kadm5.acl

    cat $DIR/assets/krb5.conf | envsubst > /etc/krb5.conf
    cat $DIR/assets/kdc.conf | envsubst > /etc/krb5kdc/kdc.conf

    log-helper info 'Kerberos 5 configuration finished'
}

function kldap_populate(){
    log-helper info "Populating LDAP backend..."
    slapd_start

    slapd_add_schemas
    slapd_apply_ldifs $DIR/ldif.d

    krb5_create_realm
    krb5_create_admin

    slapd_kerberize

    slapd_stop
    log-helper info "LDAP backend populated."
}

# Grab passwords before enabled pipefail
slapd_get_admin_password
krb5_get_kdcsrv_password
krb5_get_admsrv_password
krb5_get_master_password

set -o pipefail

slapd_configure
krb5_configure

kldap_populate

exit 0
