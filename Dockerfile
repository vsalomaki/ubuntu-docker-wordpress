FROM vsalomaki/ubuntu-docker-openresty-pagespeed:18.04.01

LABEL maintainer="vsalomaki@gmail.com"
#Forked from files by Ville Pietarinen / Geniem Oy

##
# Only use these during installation
##
ARG LANG=C.UTF-8
ARG DEBIAN_FRONTEND=noninteractive

##
# Install php7 packages from dotdeb.org
# - Dotdeb is an extra repository providing up-to-date packages for your Debian servers
## 
RUN \
    apt update \
     && apt -y upgrade \
     && apt -y --no-install-recommends install software-properties-common \
     && add-apt-repository ppa:ondrej/php \
     && apt -y --no-install-recommends install \
         apt-utils \
         curl \
         nano \
         ca-certificates \
         msmtp \
         postfix \
         less 
RUN \
        apt -y install \
        #php7.4-dev \
        php7.4-cli \
        php7.4-common \
        php7.4-apcu \
        # php7.4-apcu-bc \
        php7.4-curl \
        php7.4-json \
        php7.4-opcache \
        php7.4-readline \
        php7.4-xml \
        php7.4-zip \
        php7.4-fpm \
        php7.4-redis \
        php7.4-mongodb \
        php7.4-mysqli \
        php7.4-intl \
        php7.4-gd \
        php7.4-mbstring \
        php7.4-soap \
        php7.4-bcmath \
        #php7.4-ldap \
        php-pear \
    #&& pecl install redis \
    # Force install only cron without extra mailing dependencies
    && cd /tmp \
    && apt download cron \
    && dpkg --force-all -i cron*.deb \
    && mkdir -p /var/spool/cron/crontabs 


# Install helpers
RUN \
    ##
    # Install composer
    ##
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    ##
    # Install wp-cli
    # source: http://wp-cli.org/
    ##
    && curl -L https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp-cli \
    && chmod +rx /usr/local/bin/wp-cli \
    # Symlink it to /usr/bin as well so that cron can find this script with limited PATH
    && ln -s /usr/local/bin/wp-cli /usr/bin/wp-cli \
    ##
    # Install cronlock for running cron correctly with multi container setups
    # https://github.com/kvz/cronlock
    ##
    && curl -L https://raw.githubusercontent.com/kvz/cronlock/master/cronlock -o /usr/local/bin/cronlock \
    && chmod +rx /usr/local/bin/cronlock \
    # Symlink it to /usr/bin as well so that cron can find this script with limited PATH
    && ln -s /usr/local/bin/cronlock /usr/bin/cronlock

# Cleanup
RUN \
    apt clean \
    && apt autoremove \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* /var/log/apt/* /var/log/*.log

##
# Add Project files like nginx and php-fpm processes and configs
# Also custom scripts and bashrc
##
COPY rootfs/ /

# Run small fixes
RUN set -x \
    && mkdir -p /var/www/uploads \
    && mkdir -p /dev/cache \
    && mkdir -p /tmp/php-opcache \
    && ln -sf /usr/sbin/php-fpm7.4 /usr/sbin/php-fpm \
    && ln -sf /usr/bin/wp /usr/local/bin/wp \
    && cat /etc/disable_ipv6 >> /etc/sysctl.conf 
    
# This is for your project root
ENV PROJECT_ROOT="/var/www/project"
COPY nginx ${PROJECT_ROOT}/nginx

ENV \
    # Add interactive term
    TERM="xterm" \
    # Set defaults which can be overriden
    MYSQL_PORT="3306" \
    # Use default web port in nginx but allow it to be overridden
    # This also works correctly with flynn:
    # https://github.com/flynn/flynn/issues/3213#issuecomment-237307457
    PORT="8080" \
    # Use custom users for nginx and php-fpm
    WEB_USER="wordpress" \
    WEB_GROUP="web" \
    WEB_UID=1000 \
    WEB_GID=1001 \
    # Set defaults for redis
    REDIS_PORT="6379" \
    REDIS_DATABASE="0" \
    REDIS_PASSWORD="" \
    REDIS_SCHEME="tcp" \
    # Set defaults for NGINX fastcgi cache
    # This variable uses seconds by default
    # Time units supported are "s"(seconds), "ms"(milliseconds), "y"(years), "M"(months), "w"(weeks), "d"(days), "h"(hours), and "m"(minutes).
    # Also http response codes that are cached can be set
    NGINX_REDIS_CACHE_TTL_DEFAULT="60" \
    NGINX_REDIS_CACHE_TTL_MAX="60" \
    # Default fastcgi cache directory
    NGINX_CACHE_DIRECTORY="/dev/cache" \
    # Default operations when fastcgi stale cache is used
    NGINX_CACHE_USE_STALE="error timeout invalid_header updating http_500 http_503 http_403 http_404 http_429" \
    # Default headers for fastcgi stale- and error cache
    NGINX_CACHE_CONTROL='"max-age=60, stale-while-revalidate=300, stale-if-error=21600"'\
    # Cronlock is used to stop simultaneous cronjobs in clusterised environments
    CRONLOCK_HOST="" \
    # This is used by nginx and php-fpm
    WEB_ROOT="${PROJECT_ROOT}/web" \
    # This is used automatically by wp-cli
    WP_CORE="${PROJECT_ROOT}/web/wp" \
    # Nginx include files
    NGINX_INCLUDE_DIR="/var/www/project/nginx" \
    # Allow bigger file uploads
    NGINX_MAX_BODY_SIZE="10M" \
    # Allow storing bigger body in memory
    NGINX_BODY_BUFFER_SIZE="32k" \
    # Have sane fastcgi timeout by default
    NGINX_FASTCGI_TIMEOUT="30" \
    # Have sane fastcgi timeout by default
    NGINX_ERROR_LEVEL="warn" \
    # Have sane fastcgi timeout by default
    NGINX_ERROR_LOG="/dev/stderr" \
    # Have sane fastcgi timeout by default
    NGINX_ACCESS_LOG="/dev/stdout" \
    # Default cache key for nginx http cache
    NGINX_CACHE_KEY='wp:nginx:' \
    # PHP settings
    PHP_MEMORY_LIMIT="128M" \
    PHP_MAX_INPUT_VARS="1000" \
    PHP_ERROR_LOG="/proc/self/fd/1" \
    PHP_ERROR_LOG_LEVEL="warning" \
    PHP_ERROR_LOG_MAX_LEN="8192" \
    PHP_SESSION_REDIS_DB="0" \
    PHP_SESSION_HANDLER="files" \
    # You should count the *.php files in your project and set this number to be bigger
    # $ find . -type f -print | grep php | wc -l
    PHP_OPCACHE_MAX_FILES="8000" \
    # Amount of memory in MB to allocate for opcache
    PHP_OPCACHE_MAX_MEMORY="128" \
    # Use host machine as default SMTP_HOST
    SMTP_HOST="172.17.2.1" \
    # This folder is used to mount files into host machine
    # You should use this path for your uploads since everything else should be ephemeral
    UPLOADS_ROOT="/var/www/uploads" \
    # This can be overidden by you, it's just default for us
    TZ="Europe/Helsinki"
# Setup $TZ. Remember to run this again in your own build
    # Make sure that all files here have execute permissions
RUN dpkg-reconfigure tzdata && \
    chmod +x /etc/cont-init.d/*


# Set default path to project folder for easier running commands in project
WORKDIR ${PROJECT_ROOT}
EXPOSE ${PORT}
ENTRYPOINT ["/init"]

