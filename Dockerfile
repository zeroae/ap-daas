# Use zeroae/ap-light
# https://github.com/zeroae/ap-light
FROM zeroae/ap-light:0.6.0
MAINTAINER Patrick Sodré sodre@sodre.co

RUN groupadd -r openldap && useradd -r -g openldap openldap

RUN apt-get -y update \
    && ap-service-add :consul-agent :manta \
    && export LC_ALL=C \
    && export DEBIAN_FRONTEND=noninteractive \
    && echo "slapd slapd/no_configuration boolean true" | debconf-set-selections \
    && echo "path-include /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz" > \
        /etc/dpkg/dpkg.cfg.d/02_krb5-kdc-ldap \
    && apt-get install -y --force-yes --no-install-recommends \
        slapd ldap-utils \
        krb5-admin-server krb5-kdc-ldap \
        libsasl2-modules-gssapi-mit \
        gettext-base \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD service $AP_SERVICE_DIR

RUN ap-service-install

EXPOSE 88 88/udp 389 464/udp 749
