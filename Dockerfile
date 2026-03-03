FROM alpine:3.14

ENV TIMEZONE=Asia/Jakarta

# Install semua paket (termasuk pwgen) dengan --no-cache
RUN apk update && apk add --no-cache \
    mariadb \
    mariadb-client \
    apache2 \
    apache2-utils \
    curl \
    wget \
    tzdata \
    pwgen \
    php7-apache2 \
    php7-cli \
    php7-phar \
    php7-zlib \
    php7-zip \
    php7-bz2 \
    php7-ctype \
    php7-curl \
    php7-pdo_mysql \
    php7-mysqli \
    php7-json \
    php7-mcrypt \
    php7-xml \
    php7-dom \
    php7-iconv \
    php7-xdebug \
    php7-session \
    php7-intl \
    php7-gd \
    php7-mbstring \
    php7-apcu \
    php7-opcache \
    php7-tokenizer

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

# Download phpMyAdmin saat build
RUN mkdir -p /usr/share/webapps && \
    wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.0/phpMyAdmin-5.2.0-all-languages.tar.gz -O /tmp/phpmyadmin.tar.gz && \
    tar -xzf /tmp/phpmyadmin.tar.gz -C /usr/share/webapps && \
    mv /usr/share/webapps/phpMyAdmin-5.2.0-all-languages /usr/share/webapps/phpmyadmin && \
    rm -f /tmp/phpmyadmin.tar.gz && \
    chmod -R 755 /usr/share/webapps/phpmyadmin && \
    chown -R apache:apache /usr/share/webapps/phpmyadmin && \
    ln -s /usr/share/webapps/phpmyadmin /var/www/localhost/htdocs/phpmyadmin

# Konfigurasi timezone, MySQL, Apache, PHP, Xdebug, dan arahkan log Apache ke stdout/stderr
RUN cp /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone && \
    mkdir -p /run/mysqld && chown -R mysql:mysql /run/mysqld /var/lib/mysql && \
    mkdir -p /run/apache2 && chown -R apache:apache /run/apache2 && \
    chown -R apache:apache /var/www/localhost/htdocs/ && \
    # Enable rewrite module
    sed -i 's/#LoadModule rewrite_module modules\/mod_rewrite.so/LoadModule rewrite_module modules\/mod_rewrite.so/' /etc/apache2/httpd.conf && \
    # Set ServerName
    sed -i 's/ServerName www.example.com:80/ServerName localhost:80/' /etc/apache2/httpd.conf && \
    # Konfigurasi MariaDB
    sed -i 's/skip-networking/#skip-networking/i' /etc/my.cnf.d/mariadb-server.cnf && \
    sed -i '/mariadb\]/a log_error = \/var\/lib\/mysql\/error.log' /etc/my.cnf.d/mariadb-server.cnf && \
    sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf && \
    sed -i '/mariadb\]/a skip-external-locking' /etc/my.cnf.d/mariadb-server.cnf && \
    sed -i '/mariadb\]/a general_log = ON' /etc/my.cnf.d/mariadb-server.cnf && \
    sed -i '/mariadb\]/a general_log_file = \/var\/lib\/mysql\/query.log' /etc/my.cnf.d/mariadb-server.cnf && \
    # Konfigurasi PHP
    sed -i 's/display_errors = Off/display_errors = On/' /etc/php7/php.ini && \
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' /etc/php7/php.ini && \
    sed -i 's/post_max_size = 8M/post_max_size = 100M/' /etc/php7/php.ini && \
    sed -i 's/session.cookie_httponly =/session.cookie_httponly = true/' /etc/php7/php.ini && \
    sed -i 's/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL/' /etc/php7/php.ini && \
    # Konfigurasi Xdebug
    echo "zend_extension=xdebug.so" > /etc/php7/conf.d/xdebug.ini && \
    echo -e "\n[XDEBUG]" >> /etc/php7/conf.d/xdebug.ini && \
    echo "xdebug.remote_enable=1" >> /etc/php7/conf.d/xdebug.ini && \
    echo "xdebug.remote_connect_back=1" >> /etc/php7/conf.d/xdebug.ini && \
    echo "xdebug.idekey=PHPSTORM" >> /etc/php7/conf.d/xdebug.ini && \
    echo "xdebug.remote_log=\"/tmp/xdebug.log\"" >> /etc/php7/conf.d/xdebug.ini && \
    # Arahkan log Apache ke stdout/stderr
    sed -i '/^CustomLog/d' /etc/apache2/httpd.conf && \
    echo 'CustomLog /dev/stdout combined' >> /etc/apache2/httpd.conf && \
    sed -i '/^ErrorLog/d' /etc/apache2/httpd.conf && \
    echo 'ErrorLog /dev/stderr' >> /etc/apache2/httpd.conf

COPY entry.sh /entry.sh
RUN chmod +x /entry.sh

WORKDIR /var/www/localhost/htdocs/

EXPOSE 80 3306

ENTRYPOINT ["/entry.sh"]