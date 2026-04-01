# Stage 1: Build the assets using Node
FROM node:lts AS asset-builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Build the OSPOS app
FROM php:8.2-apache AS ospos
LABEL maintainer="jekkos"

RUN apt update && apt-get install -y libicu-dev libgd-dev
RUN a2enmod rewrite
RUN docker-php-ext-install mysqli bcmath intl gd
RUN echo "date.timezone = \"\${PHP_TIMEZONE}\"" > /usr/local/etc/php/conf.d/timezone.ini

WORKDIR /app
COPY . /app
RUN ln -s /app/*[^public] /var/www && rm -rf /var/www/html && ln -nsf /app/public /var/www/html

# Create the public/uploads directory if it doesn't exist
RUN mkdir -p /app/public/uploads /app/public/uploads/item_pics

# Create the symlink so legacy code can find the images
RUN ln -s /app/writable/uploads /app/public/uploads || true

# Fix ownership for both locations
RUN chown -R www-data:www-data /app/writable /app/public/uploads /app/writable/backup

# RUN mkdir -p /app/writable && chown -R www-data:www-data /app/writable && chmod -R 775 /app/writable
RUN chmod -R 777 /app/writable/uploads /app/writable/uploads/item_pics /app/writable/logs /app/writable/cache /app/writable/backup && chown -R www-data:www-data /app

FROM ospos AS ospos_test

COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN apt-get install -y libzip-dev wget git
RUN wget https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh -O /bin/wait-for-it.sh && chmod +x /bin/wait-for-it.sh
RUN docker-php-ext-install zip
RUN composer install -d/app
#RUN sed -i 's/backupGlobals="true"/backupGlobals="false"/g' /app/tests/phpunit.xml
WORKDIR /app/tests

CMD ["/app/vendor/phpunit/phpunit/phpunit", "/app/test/helpers"]

FROM ospos AS ospos_dev

ARG USERID
ARG GROUPID

RUN echo "Adding user uid $USERID with gid $GROUPID"
RUN ( addgroup --gid $GROUPID ospos || true ) && ( adduser --uid $USERID --gid $GROUPID ospos )

RUN yes | pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.mode=debug" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/xdebug.ini

RUN apt-get update && apt-get install -y \
    libicu-dev \
    libpng-dev \
    libzip-dev \
    && docker-php-ext-install intl gd zip mysqli bcmath
	
# Copy the composer executable from the official composer image
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN composer install --no-dev --optimize-autoloader

# Copy the built assets from Stage 1
COPY --from=asset-builder /app/public/dist /app/public/dist
COPY --from=asset-builder /app/public/resources /app/public/resources