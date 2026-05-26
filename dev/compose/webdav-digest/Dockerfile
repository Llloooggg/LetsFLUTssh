# Apache 2.4 + mod_dav + Digest auth (MD5). Built fresh from
# httpd:2.4 so the htdigest file lives inside the image.
# Username / password / realm hard-coded — local dev only.

FROM httpd:2.4-alpine@sha256:0136c2d4462f3b8ecc92bea70efdfef4d06523999ae8d7aa533969dea6db4576

# Skip the `htdigest` CLI and write the file directly. Alpine's
# apache2-utils ships an `apr_password_get` that rejects the test
# password as "too long" when no controlling TTY is available,
# regardless of the actual length. The file format is documented:
# `user:realm:MD5(user:realm:password)` — one line per user.
# Realm must agree exactly with the AuthName in httpd.conf;
# Digest hashes bake the realm into HA1.
# `apr-util-dbm_gdbm` provides the DBM driver `mod_dav_fs` needs for
# its lock database (`DAVLockDB`). Without it write verbs fail 500
# — same shape as the WebDAV Basic Dockerfile.
RUN apk add --no-cache coreutils apr-util-dbm_gdbm \
    && realm='LetsFLUTssh dev WebDAV (Digest)' \
    && ha1=$(printf '%s' "test:${realm}:test1234" | md5sum | awk '{print $1}') \
    && printf '%s:%s:%s\n' test "$realm" "$ha1" > /usr/local/apache2/conf/users.htdigest \
    && mkdir -p /var/dav /var/dav-lock \
    && chown -R daemon:daemon /var/dav /var/dav-lock

COPY httpd.conf /usr/local/apache2/conf/httpd.conf

EXPOSE 80
