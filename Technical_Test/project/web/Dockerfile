FROM php:8.2-apache

# FreeTDS-backed PDO driver. Simpler and more reliable to build than the
# Microsoft sqlsrv extension, and sufficient for queries and stored procedures.
RUN apt-get update \
    && apt-get install -y --no-install-recommends freetds-dev freetds-bin \
    && docker-php-ext-install pdo_dblib \
    && printf '[global]\n\ttds version = 7.4\n\tclient charset = UTF-8\n' > /etc/freetds/freetds.conf \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
