FROM php:7.4-apache-bullseye
LABEL maintainer="Jeroen Versteege <jeroen@kodikas.nl>"

# Debian 11 is EOL: its security updates moved from deb.debian.org to archive.debian.org
RUN sed -i 's|http://deb.debian.org/debian-security|http://archive.debian.org/debian-security|' /etc/apt/sources.list

# Install latest packages to fix a bunch of security vulnerabilities.
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get -y dist-upgrade \
    && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
        libssl-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        zlib1g-dev \
        libzip-dev \
        libicu-dev \
        g++ \
        libbase58-dev \
        libyaml-dev \
        unzip \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && docker-php-ext-install -j$(nproc) iconv \
    && docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl gettext zip bcmath

RUN a2enmod rewrite
# Install from the release tarballs, so the build doesn't depend on the (often unavailable) PECL REST API
RUN cd /tmp \
    && for pkg in mongodb-1.7.4 base58-0.1.3 yaml-2.0.4; do \
         curl -fsSL --retry 10 --retry-all-errors --retry-delay 5 -o $pkg.tgz https://pecl.php.net/get/$pkg.tgz \
         && pecl install /tmp/$pkg.tgz || exit 1; \
       done \
    && rm -f /tmp/*.tgz
RUN docker-php-ext-enable mongodb base58 yaml

RUN apt-get install -y libsodium-dev

RUN mkdir -p /app && rm -fr /var/www/html && ln -s /app /var/www/html
ADD sample/ /app
ADD php.ini /usr/local/etc/php/php.ini
# php2shell (CVE-2026-109618/109619) mitigation, PHP 7.4 gets no upstream fix
ADD conf.d/zz-security-php2shell.ini /usr/local/etc/php/conf.d/zz-security-php2shell.ini

# Set dynamic memory limit
ENV phpmemory_limit=128M
RUN sed -i 's/memory_limit = .*/memory_limit = ${phpmemory_limit}/' /usr/local/etc/php/php.ini

RUN apt-get update && apt-get install -y git
# Authorize SSH Host
RUN mkdir -p /root/.ssh && \
    chmod 0700 /root/.ssh && \
    ssh-keyscan github.com > /root/.ssh/known_hosts

ENV APACHE_DOCUMENT_ROOT=/var/www/html/www
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf

RUN apt-get install -y locales locales-all
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

RUN echo "TimeOut 1800" > /etc/apache2/conf-available/timeout.conf && \
    a2enconf timeout

# eMudhra CA key compromise (Oct 2026): Debian 11 gets no fixed ca-certificates, distrust the root ourselves.
# Kept last so no earlier apt-get layer can re-enable it.
RUN sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates --fresh