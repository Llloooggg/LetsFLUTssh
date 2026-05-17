# Apache 2.4 + mod_dav + Basic auth. Built fresh from httpd:2.4 so
# the htpasswd file lives inside the image (never on disk in the
# repo). Username / password are hard-coded to tester / testpass —
# this image is for local dev only.

FROM httpd:2.4-alpine

# `apr-util-dbm_gdbm` is the DBM provider mod_dav_fs uses for its
# per-resource lock database (`DAVLockDB`). Without it every write
# verb (PUT / MKCOL / MOVE / DELETE) fails 500 with the apache log
# entry `DSO load failed: AH00576: The DBM driver could not be
# loaded` — the lock-DB check runs ahead of the actual write, so no
# bytes ever land on disk.
RUN apk add --no-cache apache2-utils apr-util-dbm_gdbm \
    && htpasswd -bcB /usr/local/apache2/conf/users.htpasswd test test1234 \
    && mkdir -p /var/dav /var/dav-lock \
    && chown -R daemon:daemon /var/dav /var/dav-lock

COPY httpd.conf /usr/local/apache2/conf/httpd.conf

EXPOSE 80
