# Docker-LAMP

Single-container LAMP stack on Alpine Linux: Apache, PHP 8.4, MariaDB and phpMyAdmin in one image, built for small site hosting and homelab use. Website files and the database live in volumes, and Apache access/error logs stream to `docker logs`. Access can optionally be limited to a domain whitelist.

## Current Stack

| Component | Version |
| --- | --- |
| Alpine Linux | 3.24.3 |
| PHP | 8.4.27 |
| Apache | 2.4.69 |
| MariaDB | 11.8.9 |
| phpMyAdmin | 5.2.3 |

These are the tested baseline versions of the current image. Patch versions can move when Alpine packages are updated or when the pinned phpMyAdmin dependencies are refreshed.

## Key Features

- **Domain whitelist** via `ALLOWED_DOMAIN` (IP addresses and `localhost` are always allowed).
- **Persistent storage**: website files (`/var/www/localhost/htdocs`) and database (`/var/lib/mysql`) on volumes.
- **Container logging**: Apache access and error logs to `stdout`/`stderr`, readable with `docker logs`.
- **PHP extensions**: mysqli, pdo_mysql, pdo_sqlite, gd, intl, mbstring, zip, opcache, apcu, simplexml, xmlreader, xmlwriter, bz2, fileinfo, phar, session, tokenizer, curl, dom, iconv.
- **phpMyAdmin** 5.2.3 served at `/phpmyadmin/` from the same container.
- **Healthcheck** on the web server, plus MariaDB datadir auto-initialization and auto-upgrade for existing volumes.
- **Signal-safe shutdown**: `docker stop` is handled through the whole container lifecycle, including while the database is being initialized or upgraded.

## Quick Start

```bash
git clone https://github.com/rizkybs70/docker-lamp.git
cd docker-lamp
docker build -t docker-lamp:php84 .
```

The build fetches Alpine packages, the phpMyAdmin release archive, Composer and the phpMyAdmin dependency tree from official sources, so the first build needs internet access and no local vendor folder.

```bash
docker run -d \
  --name docker-lamp \
  -e MYSQL_ROOT_PASSWORD='***' \
  -e ALLOWED_DOMAIN='example.com,www.example.com' \
  -p 8080:80 \
  -v /srv/lamp/website:/var/www/localhost/htdocs \
  -v /srv/lamp/mysql:/var/lib/mysql \
  --stop-timeout 60 \
  --restart unless-stopped \
  docker-lamp:php84
```

```bash
docker logs -f docker-lamp
```

```yaml
# docker-compose.yml
services:
  lamp:
    image: docker-lamp:php84
    stop_grace_period: 60s
    ports:
      - "8080:80"
    volumes:
      - /srv/lamp/website:/var/www/localhost/htdocs
      - /srv/lamp/mysql:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: "***"
      ALLOWED_DOMAIN: "example.com,www.example.com"
```

Open `http://localhost:8080/` for the website and `http://localhost:8080/phpmyadmin/` for phpMyAdmin. MariaDB is not published to the host by default: only add `-p 3306:3306` when an external client really needs direct database access.

`--stop-timeout 60` (compose: `stop_grace_period: 60s`) is a safety margin, not a workaround. A steady-state stop finishes in seconds, but a stop that arrives while MariaDB is still initializing or upgrading a volume lets that work finish before the container exits, and a database flushing dirty pages on slow storage can take longer than Docker's 10 second default.

### Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | yes | MariaDB root password; applied when the data directory is initialized for the first time. |
| `ALLOWED_DOMAIN` | no | Comma-separated hostname whitelist. Unset or empty allows every hostname. |
| `PMA_BLOWFISH_SECRET` | no | phpMyAdmin blowfish secret. If unset, one is generated and stored in `/var/lib/phpmyadmin`. |

The image ships no credentials and no host-specific configuration: everything comes from the environment or the mounted volumes.

### Database upgrade

Migrating an existing `/var/lib/mysql` volume from an older stack (for example MariaDB 10.6 to 11.8) is not covered by the automatic upgrade step. That step only applies in-place upgrades to a datadir already in the format of the running MariaDB series. For a major version jump: stop the old container, take a full backup of both the website volume and a consistent database dump or datadir copy, test the migration on a copy, and only then point the new container at the migrated volume. Never assume an existing datadir is safe to hand to a higher major version without that rehearsal.

## Changelog

### 2026-10-31 - Security Modernization

- Rebased on Alpine 3.24.3 with Apache 2.4.69, PHP 8.4.27 and MariaDB 11.8.9 (Alpine 3.14, PHP 7.4 and MariaDB 10.6 removed).
- phpMyAdmin updated to 5.2.3, still verified against its published SHA-256 checksum at build time.
- phpMyAdmin dependency management modernized: dependencies are now resolved during the build from official sources, starting from phpMyAdmin's own locked versions and moving only the packages with known advisories. The manually prepared `pma-vendor/` folder is gone, and the build fails if the resolved tree loses packages or drifts from the pinned versions. The resolved `composer.lock` is shipped in the image so audit tools read the versions that are actually vendored.
- Refreshed dependencies with known advisories: `twig/twig` 3.30.0, `symfony/cache` 5.4.52, `symfony/expression-language` 5.4.54, `symfony/process` 5.4.51, `paragonie/sodium_compat` 1.24.2, `symfony/deprecation-contracts` 3.7.1.
- The resolved tree matches the release archive package for package (58 packages), so the runtime dependencies phpMyAdmin ships with stay complete: WebAuthn, TCPDF, Twig, Symfony, BaconQrCode, U2F and the rest.
- Added the PHP XML (simplexml, xmlreader, xmlwriter) and SQLite (pdo_sqlite) extensions required by phpMyAdmin internals.
- Improved PHP CLI compatibility: `php` now resolves to `php84`.
- Removed Xdebug from the image.
- Hardened PHP runtime settings: `display_errors` off, `expose_php` off, errors to stderr, HTTP-only session cookies, 100M upload/post limits.
- Added `mod_rewrite`, Apache logging to `stdout`/`stderr`, a container healthcheck and automatic MariaDB datadir upgrade for existing volumes.
- Improved graceful shutdown: the entrypoint now handles `SIGTERM`/`SIGINT` for the whole lifecycle. A stop request that lands while the datadir is being initialized or a MariaDB upgrade is running no longer gets ignored until the stop grace period expires and the container is killed; that work is allowed to finish and the container then exits cleanly. An intentional stop exits `0` instead of `1`, Apache and MariaDB shut down in order, and no child process is left behind.
- Validated 2026-10-31 on both architectures: AMD64 built and runtime-tested natively on x86_64, ARM64 cross-built on x86_64 and runtime-tested natively on aarch64. Checks covered versions, PHP extensions, phpMyAdmin HTTP and login page, domain whitelist allow/deny, MariaDB read/write, restart persistence, healthcheck, and repeated start/stop/restart cycles including stops during initialization. Trivy reports no vulnerability on either image, and the dependency tree is identical across both (58 packages, same versions).

### Legacy stack (before 2026-10-31)

Alpine 3.14, Apache 2.4, PHP 7.4 with Xdebug, MariaDB 10.6, phpMyAdmin 5.2.0.

## Architecture Support

| Architecture | Status |
| --- | --- |
| `linux/amd64` | Tested natively on x86_64 (built and run on the same architecture). |
| `linux/arm64` | Tested natively on aarch64. The image is cross-built on an x86_64 host and then imported and run on ARM64 hardware. |

A native ARM64 run proves the image works on the ARM64 host used for testing; it does not guarantee every ARM64 device or kernel is compatible. Older ARM boards, unusual page sizes or restricted kernels can still behave differently and should be tested before being trusted.

## Credits

Based on [j1cs/docker-lamp](https://github.com/j1cs/docker-lamp), with domain whitelisting, `docker logs` friendly logging and persistent volumes added in this fork, plus the 2026 security modernization.
