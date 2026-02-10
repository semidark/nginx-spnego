FROM ubuntu:24.04 AS build

ENV NGINX_VERSION=1.24.0

##PREPARE SOURCE
RUN mkdir /opt/build
ADD http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz /opt/build/
RUN tar -C /opt/build -xf /opt/build/nginx-${NGINX_VERSION}.tar.gz
ADD https://github.com/stnoonan/spnego-http-auth-nginx-module.git /opt/build/nginx-${NGINX_VERSION}/spnego-http-auth-nginx-module/

WORKDIR /opt/build/nginx-${NGINX_VERSION}
RUN apt update && apt install -y gcc make libpcre2-dev libssl-dev zlib1g-dev libxml2-dev \
                      libxslt-dev libgd-dev libperl-dev libextutils-depends-perl libgeoip-dev libkrb5-dev
RUN ./configure \
    --with-cc-opt='-g -O2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -ffile-prefix-map=/build/nginx-5QYLpr/nginx-1.24.0=. -flto=auto -ffat-lto-objects -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fdebug-prefix-map=/build/nginx-5QYLpr/nginx-1.24.0=/usr/src/nginx-1.24.0-2ubuntu7.3 -fPIC -Wdate-time -D_FORTIFY_SOURCE=3' \
    --with-ld-opt='-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -Wl,-z,relro -Wl,-z,now -fPIC' \
    --prefix=/usr/share/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --http-log-path=/var/log/nginx/access.log \
    --error-log-path=stderr \
    --lock-path=/var/lock/nginx.lock \
    --pid-path=/run/nginx.pid \
    --modules-path=/usr/lib/nginx/modules \
    --http-client-body-temp-path=/var/lib/nginx/body \
    --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
    --http-proxy-temp-path=/var/lib/nginx/proxy \
    --http-scgi-temp-path=/var/lib/nginx/scgi \
    --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
    --with-compat \
    --with-debug \
    --with-pcre-jit \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_v2_module \
    --with-http_dav_module \
    --with-http_slice_module \
    --with-threads \
    --with-http_addition_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_sub_module \
    --with-mail_ssl_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_geoip_module=dynamic \
    --with-http_image_filter_module=dynamic \
    --with-http_perl_module=dynamic \
    --with-http_xslt_module=dynamic \
    --with-mail=dynamic \
    --with-stream=dynamic \
    --with-stream_geoip_module=dynamic \
    --add-module=spnego-http-auth-nginx-module

RUN make

FROM ubuntu:24.04
EXPOSE 80/tcp
EXPOSE 443/tcp
# TODO: Check if libgssapi-krb5-2 is needed
RUN apt update && apt install -y nginx libgssapi-krb5-2
COPY --from=build /opt/build/nginx-1.24.0/objs/nginx /usr/sbin/nginx
ADD default /etc/nginx/sites-enabled/default
ADD index.html /var/www/html/index.html
ENTRYPOINT ["/usr/sbin/nginx", "-g daemon off;"]

