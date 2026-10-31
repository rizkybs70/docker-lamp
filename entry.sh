#!/bin/sh
set -eu
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

# Single stop handler for the whole script. A stop request never aborts datadir
# initialization or a MariaDB upgrade halfway; each phase checks the flag at safe
# boundaries and exits cleanly (0) once the phase has completed.
stopping=0
trap 'stopping=1' TERM INT

mkdir -p /run/mysqld /run/apache2 /var/lib/phpmyadmin/tmp
chown mysql:mysql /run/mysqld
chown apache:apache /run/apache2 /var/lib/phpmyadmin /var/lib/phpmyadmin/tmp

allowed_domain="${ALLOWED_DOMAIN:-}"
if [ -n "$allowed_domain" ]; then
    pattern=""; old_ifs="$IFS"; IFS=,
    for domain in $allowed_domain; do
        domain=$(printf '%s' "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$domain" ] || continue
        case "$domain" in *[!A-Za-z0-9.-]*|.*|*..*|*.-*|-.*|*.) echo "Invalid ALLOWED_DOMAIN value" >&2; exit 1;; esac
        escaped=$(printf '%s' "$domain" | sed 's/[.[\^$*+?(){}|]/\\&/g')
        if [ -n "$pattern" ]; then pattern="$pattern|$escaped"; else pattern="$escaped"; fi
    done
    IFS="$old_ifs"
    [ -n "$pattern" ] || { echo "ALLOWED_DOMAIN contains no valid domain" >&2; exit 1; }
    cat > /etc/apache2/conf.d/whitelist.conf <<EOF
RewriteEngine On
RewriteCond %{HTTP_HOST} !^(\d{1,3}\.){3}\d{1,3}(:[0-9]+)?$ [NC]
RewriteCond %{HTTP_HOST} !^localhost(:[0-9]+)?$ [NC]
RewriteCond %{HTTP_HOST} !^(www\.)?(${pattern})(:[0-9]+)?$ [NC]
RewriteRule ^ - [F,L]
EOF
else
    rm -f /etc/apache2/conf.d/whitelist.conf
fi

fresh_datadir=0
if [ ! -f /var/lib/mysql/ibdata1 ]; then
    fresh_datadir=1
    echo "Initializing MariaDB datadir"
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
    mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid &
    db_pid=$!
    ready=0
    for _ in $(seq 1 60); do
        if mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot ping --silent >/dev/null 2>&1; then ready=1; break; fi
        sleep 1
    done
    [ "$ready" -eq 1 ] || { echo "MariaDB initialization timeout" >&2; exit 1; }
    if [ "$stopping" -eq 1 ]; then
        echo "Stop requested during MariaDB initialization: completing initialization before exit"
    fi
    mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot password "$MYSQL_ROOT_PASSWORD"
    mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot --password="$MYSQL_ROOT_PASSWORD" shutdown
    wait "$db_pid" 2>/dev/null || true
    if [ "$stopping" -eq 1 ]; then
        echo "MariaDB datadir ready, exiting on stop request"
        exit 0
    fi
fi

if [ "$fresh_datadir" -eq 0 ] && [ ! -f /var/lib/mysql/.lamp-mariadb-upgraded ]; then
    echo "Running MariaDB upgrade for existing datadir"
    mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid &
    db_pid=$!
    ready=0
    for _ in $(seq 1 90); do
        if mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot -p"$MYSQL_ROOT_PASSWORD" ping --silent >/dev/null 2>&1; then ready=1; break; fi
        sleep 1
    done
    [ "$ready" -eq 1 ] || { echo "MariaDB existing-datadir readiness timeout" >&2; exit 1; }
    if [ "$stopping" -eq 1 ]; then
        echo "Stop requested during MariaDB upgrade: completing upgrade before exit"
    fi
    mariadb-upgrade --socket=/run/mysqld/mysqld.sock -uroot -p"$MYSQL_ROOT_PASSWORD" --force
    mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot -p"$MYSQL_ROOT_PASSWORD" shutdown
    wait "$db_pid" 2>/dev/null || true
    : > /var/lib/mysql/.lamp-mariadb-upgraded
    if [ "$stopping" -eq 1 ]; then
        echo "MariaDB upgrade complete, exiting on stop request"
        exit 0
    fi
fi

httpd -t
httpd -D FOREGROUND & apache_pid=$!
mariadbd --user=mysql --datadir=/var/lib/mysql --bind-address=0.0.0.0 --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid & db_pid=$!

stop_services() {
    kill "$apache_pid" "$db_pid" 2>/dev/null || true
    wait "$apache_pid" 2>/dev/null || true
    wait "$db_pid" 2>/dev/null || true
}

while kill -0 "$apache_pid" 2>/dev/null && kill -0 "$db_pid" 2>/dev/null; do
    if [ "$stopping" -eq 1 ]; then
        echo "Stop requested: shutting down Apache and MariaDB"
        stop_services
        echo "Shutdown complete"
        exit 0
    fi
    sleep 2
done
echo "Apache or MariaDB exited" >&2
exit 1
