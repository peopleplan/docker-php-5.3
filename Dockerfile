FROM debian:jessie
MAINTAINER David Hong <david.hong@peopleplan.com.au>

ENV DEBIAN_FRONTEND=noninteractive \
	PHP_INI_DIR=/usr/local/etc/php \
	PHP_VERSION=5.3.29 \
	GPG_KEYS="0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491" \
	OPENSSL_VERSION=1.0.2e

# persistent / runtime deps / php deps
RUN apt-get update \
	&& apt-get install -yq --no-install-recommends \
		ca-certificates \
		curl \
		libpcre3 \
		librecode0 \
		libmysqlclient-dev \
		libsqlite3-0 \
		libxml2 \
		autoconf \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c

RUN mkdir -p "$PHP_INI_DIR/conf.d" \
	&& set -xe \
	&& for key in $GPG_KEYS; do \
		gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done

# compile openssl, otherwise --with-openssl won't work
RUN cd /tmp \
	&& mkdir openssl \
	&& curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
	&& curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
	&& gpg --verify openssl.tar.gz.asc \
	&& tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
	&& cd /tmp/openssl \
	&& ./config && make && make install \
	&& rm -rf /tmp/*

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
		autoconf2.13 \
		libcurl4-openssl-dev \
		libpcre3-dev \
		libreadline6-dev \
		librecode-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		xz-utils \
	" \
	&& set -x \
	&& apt-get install -y $buildDeps --no-install-recommends \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
	&& gpg --verify php.tar.xz.asc \
	&& mkdir -p /usr/src/php \
	&& tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
	&& rm php.tar.xz* \
	&& cd /usr/src/php \
	&& ./configure \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--enable-fpm \
		--with-fpm-user=www-data \
		--with-fpm-group=www-data \
		--disable-cgi \
		--disable-debug \
		--enable-bcmath \
		--enable-calendar \
		--enable-exif \
		--enable-ftp \
		--enable-mbstring \
		--enable-mysqlnd \
		--enable-pcntl \
		--enable-soap \
		--enable-sockets \
		--enable-zip \
		--with-curl \
		--with-mysql \
		--with-openssl=/usr/local/ssl \
		--with-readline \
		--with-recode \
		--with-zlib \
	&& make -j"$(nproc)" \
	&& make install \
	&& { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
	&& apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
	&& make clean

COPY docker-php-* /usr/local/bin/

# php extensions: gd iconv mcrypt
RUN apt-get install -yq --no-install-recommends \
	libfreetype6-dev \
	libjpeg62-turbo-dev \
	libmcrypt-dev \
	libpng12-dev

RUN mkdir -p /usr/include/freetype2/freetype \
	&& ln -s /usr/include/freetype2/freetype.h /usr/include/freetype2/freetype/freetype.h \
	&& docker-php-ext-install iconv mcrypt \
	&& docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
	&& docker-php-ext-install gd

# clean up apt after install all the dependencies
RUN apt-get clean \
	&& rm -r /var/lib/apt/lists/*

# configure php-fpm
COPY php.ini "$PHP_INI_DIR"
COPY php-fpm.conf /usr/local/etc/

# volumes
WORKDIR /var/www/html
VOLUME /var/www/html

EXPOSE 9000
CMD ["php-fpm"]
