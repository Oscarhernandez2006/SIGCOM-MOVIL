# API móvil de SIGCOM (Laravel en ./backend) para Dokploy: PHP-FPM + Nginx en el puerto 8080.
FROM serversideup/php:8.4-fpm-nginx

ENV PHP_OPCACHE_ENABLE=1 \
    AUTORUN_ENABLED=true \
    # La base es la de producción compartida con la web: nunca correr migraciones al desplegar.
    AUTORUN_LARAVEL_MIGRATION=false \
    AUTORUN_LARAVEL_STORAGE_LINK=false \
    SSL_MODE=off

WORKDIR /var/www/html

COPY --chown=www-data:www-data backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --no-interaction --prefer-dist

COPY --chown=www-data:www-data backend/ ./
RUN composer dump-autoload --optimize --no-dev \
    && php artisan package:discover --ansi

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
    CMD curl -fsS http://localhost:8080/api/health || exit 1
