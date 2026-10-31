# --- phpMyAdmin dependency builder ---------------------------------------------------
# Resolves phpMyAdmin's runtime dependency tree from official sources at build time so a
# fresh `git clone` can be built directly, without a pre-prepared pma-vendor/ folder.
FROM alpine:3.24.3 AS pma-deps

ARG PMA_VERSION=5.2.3
ARG PMA_SHA256=12ba1c425fa4071abbd4e7668c9ebdeac0b0755a467a6d6d5026122bb47c102b

ARG COMPOSER_VERSION=2.10.3
ARG COMPOSER_SHA256=7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6

# Security pins: lowest dependency versions that fix the advisories affecting the
# dependency set locked by phpMyAdmin 5.2.3. Keep in sync with the README changelog.
ARG TWIG_VERSION=3.30.0
ARG SYMFONY_CACHE_VERSION=5.4.52
ARG SYMFONY_EXPRESSION_LANGUAGE_VERSION=5.4.54
ARG SYMFONY_PROCESS_VERSION=5.4.51
ARG SYMFONY_DEPRECATION_CONTRACTS_VERSION=3.7.1
ARG SODIUM_COMPAT_VERSION=1.24.2

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1

# Platform requirements of phpMyAdmin (ext-hash/json/pcre ship inside php84) plus what
# Composer itself needs to resolve and unpack distributions.
# git: source-download fallback for packages without a dist archive (builder stage only).
RUN apk add --no-cache ca-certificates git php84 php84-ctype php84-curl php84-dom php84-iconv \
    php84-mbstring php84-mysqli php84-openssl php84-phar php84-simplexml php84-tokenizer \
    php84-xml php84-xmlwriter php84-zip wget \
    && update-ca-certificates

RUN wget -q "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" -O /usr/local/bin/composer.phar \
    && echo "${COMPOSER_SHA256}  /usr/local/bin/composer.phar" | sha256sum -c -

WORKDIR /pma

# Keep the release archive's own dependency metadata as the reference for the build-time
# verification below, then drop the shipped vendor tree so it is rebuilt from scratch.
RUN wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" -O /tmp/phpmyadmin.tar.gz \
    && echo "${PMA_SHA256}  /tmp/phpmyadmin.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/phpmyadmin.tar.gz -C /pma --strip-components=1 \
    && rm -rf /tmp/phpmyadmin.tar.gz \
    && cp /pma/vendor/composer/installed.json /pma/reference-installed.json \
    && cp /pma/composer.lock /pma/reference-composer.lock \
    && rm -rf /pma/vendor

# phpMyAdmin declares several packages it loads at runtime (WebAuthn, 2FA, TCPDF export,
# thecodingmachine/safe) as require-dev, and its release archive ships them anyway. Promote
# those to require so `composer update --no-dev` keeps the runtime closure intact, drop the
# remaining dev requirements, and leave every other version at its locked value.
RUN cat > /tmp/prepare-composer-json.php <<'EOF'
<?php
$composerFile = '/pma/composer.json';
$lock = json_decode((string) file_get_contents('/pma/reference-composer.lock'), true, 512, JSON_THROW_ON_ERROR);
$data = json_decode((string) file_get_contents($composerFile), true, 512, JSON_THROW_ON_ERROR);

$locked = [];
foreach ($lock['packages'] as $package) {
    $locked[$package['name']] = ltrim($package['version'], 'v');
}

$promoted = [];
foreach (array_keys($data['require-dev'] ?? []) as $name) {
    if (! isset($locked[$name])) {
        continue;
    }
    $data['require'][$name] = $locked[$name];
    $promoted[] = $name . ' ' . $locked[$name];
}

unset($data['require-dev'], $data['scripts'], $data['config']['allow-plugins']);
file_put_contents($composerFile, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n");
printf("promoted to require: %s\n", implode(', ', $promoted));
EOF

RUN php84 /tmp/prepare-composer-json.php \
    && php84 /usr/local/bin/composer.phar update --no-dev --no-scripts --no-plugins --prefer-dist \
        --with-all-dependencies \
        "twig/twig:${TWIG_VERSION}" \
        "symfony/cache:${SYMFONY_CACHE_VERSION}" \
        "symfony/expression-language:${SYMFONY_EXPRESSION_LANGUAGE_VERSION}" \
        "symfony/process:${SYMFONY_PROCESS_VERSION}" \
        "symfony/deprecation-contracts:${SYMFONY_DEPRECATION_CONTRACTS_VERSION}" \
        "paragonie/sodium_compat:${SODIUM_COMPAT_VERSION}"

# Build-time guard: refuse to produce a layer when the resolved tree lost a package that the
# release archive ships, when a security pin drifted, or when a runtime class cannot load.
RUN cat > /tmp/verify-pma-vendor.php <<'EOF'
<?php
$pins = [
    'twig/twig' => '3.30.0',
    'symfony/cache' => '5.4.52',
    'symfony/expression-language' => '5.4.54',
    'symfony/process' => '5.4.51',
    'symfony/deprecation-contracts' => '3.7.1',
    'paragonie/sodium_compat' => '1.24.2',
];

$readInstalled = static function (string $file): array {
    $data = json_decode((string) file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    $packages = $data['packages'] ?? $data;
    $versions = [];
    foreach ($packages as $package) {
        $versions[$package['name']] = ltrim($package['version'], 'v');
    }
    return $versions;
};

$reference = $readInstalled('/pma/reference-installed.json');
$resolved = $readInstalled('/pma/vendor/composer/installed.json');

$errors = [];
$missing = array_diff_key($reference, $resolved);
foreach (array_keys($missing) as $name) {
    $errors[] = 'missed a package the release archive ships: ' . $name;
}
foreach ($pins as $name => $version) {
    if (($resolved[$name] ?? null) !== $version) {
        $errors[] = sprintf('%s resolved to %s, expected %s', $name, $resolved[$name] ?? 'nothing', $version);
    }
}

require '/pma/vendor/autoload.php';
$classes = [
    'TCPDF',
    'Webauthn\PublicKeyCredentialSource',
    'Webmozart\Assert\Assert',
    'BaconQrCode\Encoder\Encoder',
    'PragmaRX\Google2FA\Google2FA',
    'PragmaRX\Google2FAQRCode\Google2FA',
    'Safe\Exceptions\FilesystemException',
    'Ramsey\Uuid\Uuid',
    'League\Uri\Uri',
    'Brick\Math\BigInteger',
    'DASPRiD\Enum\AbstractEnum',
    'CodeLts\U2F\U2FServer\U2FServer',
    'Symfony\Component\Cache\Adapter\FilesystemAdapter',
    'PhpMyAdmin\Twig\I18nExtension',
    'Slim\Psr7\Factory\ServerRequestFactory',
];
foreach ($classes as $class) {
    if (! class_exists($class)) {
        $errors[] = 'not autoloadable: ' . $class;
    }
}

if ($errors !== []) {
    fwrite(STDERR, "phpMyAdmin dependency check failed:\n - " . implode("\n - ", $errors) . "\n");
    exit(1);
}
printf(
    "phpMyAdmin vendor OK: %d packages (%d expected), twig %s, symfony/cache %s\n",
    count($resolved),
    count($reference),
    $resolved['twig/twig'],
    $resolved['symfony/cache']
);
$extra = array_diff_key($resolved, $reference);
if ($extra !== []) {
    printf("additional packages resolved by the security pins: %s\n", implode(', ', array_map(
        static fn ($name, $version) => $name . ' ' . $version,
        array_keys($extra),
        array_values($extra)
    )));
}
EOF
RUN php84 /tmp/verify-pma-vendor.php \
    && rm -f /tmp/prepare-composer-json.php /tmp/verify-pma-vendor.php /pma/reference-installed.json /pma/reference-composer.lock

# --- LAMP runtime image ---------------------------------------------------------------
FROM alpine:3.24.3

ARG PMA_VERSION=5.2.3
ARG PMA_SHA256=12ba1c425fa4071abbd4e7668c9ebdeac0b0755a467a6d6d5026122bb47c102b

ENV TIMEZONE=Asia/Jakarta \
    PHP_INI_DIR=/etc/php84

RUN apk add --no-cache \
    apache2 apache2-utils ca-certificates curl mariadb mariadb-client mariadb-server-utils tzdata wget \
    php84 php84-apache2 php84-bz2 php84-ctype php84-curl php84-dom php84-fileinfo \
    php84-gd php84-iconv php84-intl php84-mbstring php84-mysqli php84-opcache \
    php84-pdo_mysql php84-pdo_sqlite php84-pecl-apcu php84-phar php84-session php84-simplexml \
    php84-tokenizer php84-xml php84-xmlreader php84-xmlwriter php84-zip \
    && update-ca-certificates

RUN test ! -e /usr/local/bin/php \
    && ln -s /usr/bin/php84 /usr/local/bin/php \
    && mkdir -p /usr/share/webapps /run/mysqld /run/apache2 /var/www/localhost/htdocs \
    /etc/phpmyadmin /var/lib/phpmyadmin/tmp \
    && wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" -O /tmp/phpmyadmin.tar.gz \
    && echo "${PMA_SHA256}  /tmp/phpmyadmin.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/phpmyadmin.tar.gz -C /usr/share/webapps \
    && mv "/usr/share/webapps/phpMyAdmin-${PMA_VERSION}-all-languages" /usr/share/webapps/phpmyadmin \
    && rm -f /tmp/phpmyadmin.tar.gz \
    && rm -rf /usr/share/webapps/phpmyadmin/vendor \
    && chmod -R 755 /usr/share/webapps/phpmyadmin \
    && chown -R apache:apache /usr/share/webapps/phpmyadmin /var/lib/phpmyadmin \
    && cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime \
    && echo "${TIMEZONE}" > /etc/timezone \
    && chown -R mysql:mysql /run/mysqld /var/lib/mysql \
    && chown -R apache:apache /run/apache2

RUN sed -i '/^[[:space:]]*skip-networking[[:space:]]*$/d' /etc/my.cnf.d/mariadb-server.cnf

RUN sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf \
    && sed -i 's#^ErrorLog .*#ErrorLog /dev/stderr#' /etc/apache2/httpd.conf \
    && sed -i '/^CustomLog/d' /etc/apache2/httpd.conf \
    && printf '\nServerName localhost:80\nCustomLog /dev/stdout combined\n' >> /etc/apache2/httpd.conf \
    && cat > /etc/apache2/conf.d/phpmyadmin.conf <<'EOF'
Alias /phpmyadmin /usr/share/webapps/phpmyadmin
<Directory /usr/share/webapps/phpmyadmin>
    Require all granted
    AllowOverride None
</Directory>
EOF

RUN cat > /etc/php84/conf.d/zz-lamp-production.ini <<'EOF'
display_errors=Off
display_startup_errors=Off
log_errors=On
error_log=/dev/stderr
expose_php=Off
error_reporting=E_ALL
session.cookie_httponly=1
upload_max_filesize=100M
post_max_size=100M
opcache.enable=1
opcache.validate_timestamps=1
EOF

RUN cat > /etc/phpmyadmin/config.inc.php <<'EOF'
<?php
$secret = getenv('PMA_BLOWFISH_SECRET');
$secret_file = '/var/lib/phpmyadmin/blowfish_secret';
if (!$secret && is_readable($secret_file)) $secret = trim((string) file_get_contents($secret_file));
if (!$secret) {
    $secret = bin2hex(random_bytes(32));
    @file_put_contents($secret_file, $secret, LOCK_EX);
    @chmod($secret_file, 0600);
}
$cfg['blowfish_secret'] = $secret;
$i = 1;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = '127.0.0.1';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
$cfg['TempDir'] = '/var/lib/phpmyadmin/tmp';
EOF

# Dependency tree resolved in the pma-deps stage: no local vendor folder required.
COPY --from=pma-deps /pma/vendor/ /usr/share/webapps/phpmyadmin/vendor/
# Ship the resolved lock so audit tools read the versions actually vendored, not the archive's stale one.
COPY --from=pma-deps /pma/composer.lock /usr/share/webapps/phpmyadmin/composer.lock
COPY entry.sh /entry.sh
RUN chmod 0755 /entry.sh
WORKDIR /var/www/localhost/htdocs
EXPOSE 80 3306
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD curl -fsS http://127.0.0.1/ >/dev/null || exit 1
ENTRYPOINT ["/entry.sh"]

