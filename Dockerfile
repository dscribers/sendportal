FROM bkuhl/fpm-nginx:7.4.2 as app

# Install OS dependencies
RUN apk update && apk add zip unzip libzip-dev postgresql-dev git php-pcntl

# Install docker dependencies
RUN docker-php-ext-install zip mysqli pdo pdo_pgsql pcntl

# Install shadow for usermod etc
RUN echo http://dl-2.alpinelinux.org/alpine/edge/community/ >> /etc/apk/repositories
RUN apk --no-cache add shadow

RUN composer self-update
RUN composer self-update --2
RUN composer global remove hirak/prestissimo

# Set working directory
WORKDIR /var/www/html

ARG PUID=1000
ARG PGID=1000
ENV PUID ${PUID}
ENV PGID ${PGID}

# Create dscribe user
RUN groupadd -g ${PGID} dscribe && \
    useradd -u ${PUID} -g dscribe -m dscribe -G www-data,root && \
    usermod -p "dscribe" dscribe -s /bin/sh

USER dscribe

# Copy composer files
COPY composer.* ./

# Copy files to autoload
COPY database ./database
COPY tests ./tests

# Install composer packages
RUN composer install --no-scripts --prefer-dist

USER root

COPY docker/crontab.txt .

# Install cronjob
ARG CRONJOBS=false

RUN if [ ${CRONJOBS} = true ]; then \
        crontab -u dscribe crontab.txt \
    ;fi

RUN rm crontab.txt

# Copy the application files to the container
COPY --chown=dscribe:www-data . ./

USER dscribe

# Create cache data directory if not exists
RUN mkdir -p storage/framework/cache/data

# Finish comoser install
RUN composer run-script post-autoload-dump

RUN php artisan config:cache

RUN php artisan event:cache

RUN php artisan route:cache

USER root

# Adds composer bin directories to environment path
ENV PATH="~/.composer/vendor/bin:./vendor/bin:${PATH}"

# Set correct permissions for storage and bootstrap directories
RUN find storage/ -type f -print0 | xargs -0 chmod 664 && \
    find storage/ -type d -print0 | xargs -0 chmod 775 && \
    find bootstrap/cache/ -type f -print0 | xargs -0 chmod 664 && \
    find bootstrap/cache/ -type d -print0 | xargs -0 chmod 775

COPY ./docker/php/local.ini /usr/local/etc/php/conf.d/local.ini
COPY ./docker/nginx/conf.d/ /etc/nginx/conf.d/
