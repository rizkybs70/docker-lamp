#!/bin/sh

# ==================================================
# Whitelist domain berdasarkan environment ALLOWED_DOMAIN
# Bisa multiple domain dipisah koma, contoh: "example.com,test.org"
# Jika kosong/tidak diset, tidak ada pembatasan
# ==================================================
if [ ! -z "$ALLOWED_DOMAIN" ]; then
    echo "Mengaktifkan whitelist domain: $ALLOWED_DOMAIN (dengan pengecualian akses via IP dan localhost)"
    # Ubah daftar domain (pisah koma) menjadi pattern regex: (domain1|domain2|...)
    # Hilangkan spasi, lalu escape titik
    DOMAINS_PATTERN=$(echo "$ALLOWED_DOMAIN" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\./\\./g' | tr '\n' '|' | sed 's/|$//')
    cat > /etc/apache2/conf.d/whitelist.conf <<EOF
RewriteEngine On
# Izinkan akses langsung via IP (IPv4)
RewriteCond %{HTTP_HOST} ^(\d{1,3}\.){3}\d{1,3}$ [OR]
# Izinkan localhost
RewriteCond %{HTTP_HOST} ^localhost$ [OR]
# Izinkan domain yang diizinkan (dengan atau tanpa www)
RewriteCond %{HTTP_HOST} ^(www\.)?(${DOMAINS_PATTERN})$ [NC]
RewriteRule ^ - [L]
# Selain itu, blokir dengan 403
RewriteRule ^ - [F]
EOF
else
    rm -f /etc/apache2/conf.d/whitelist.conf
fi

# ==================================================
# Jalankan Apache di background (agar log ke stdout/stderr)
# ==================================================
echo "Starting httpd"
httpd -D FOREGROUND &
echo "Done httpd"

# ==================================================
# Inisialisasi database MySQL jika perlu
# ==================================================
echo "Checking /var/lib/mysql folder"
if [ ! -f /var/lib/mysql/ibdata1 ]; then 
    echo "Installing db"
    mariadb-install-db --user=mysql --ldata=/var/lib/mysql > /dev/null
    echo "Installed"
fi;

# Validasi password root
if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    echo >&2 'error: database is uninitialized and password option is not specified '
    echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_RANDOM_ROOT_PASSWORD'
    exit 1
fi

# Generate password acak jika diminta
if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    echo "Using random password"
    MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
    echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
    echo "Done"
fi

tfile=`mktemp`
if [ ! -f "$tfile" ]; then
    exit 1
fi

cat << EOF > $tfile
USE mysql;
DELETE FROM user;
FLUSH PRIVILEGES;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY "$MYSQL_ROOT_PASSWORD" WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
UPDATE user SET password=PASSWORD("") WHERE user='root' AND host='localhost';
FLUSH PRIVILEGES;
EOF

echo "Querying user"
/usr/bin/mysqld --user=root --bootstrap --verbose=0 < $tfile
rm -f $tfile
echo "Done query"

# ==================================================
# Jalankan MySQL sebagai proses utama
# ==================================================
echo "Starting mariadb database"
exec /usr/bin/mysqld --user=root --bind-address=0.0.0.0