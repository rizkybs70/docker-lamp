# Docker-LAMP

*This Docker image provides a LAMP stack (Linux, Apache, MySQL, PHP) with additional security features, built from scratch on Alpine Linux.*

**Source:** Based on [j1cs/docker-lamp](https://github.com/j1cs/docker-lamp) with enhancements:  
✅ Whitelist domain filtering  
✅ Multi-architecture support  
✅ Optimized logging to `docker logs`  
✅ Persistent data volumes  

---

## 🔥 Features

- **Base:** Alpine Linux 3.14 (lightweight & secure)  
- **Web Server:** Apache 2.4 with `mod_rewrite` enabled  
- **Database:** MariaDB 10.6 (MySQL compatible)  
- **PHP:** PHP 7.4 with common extensions (mysqli, pdo_mysql, gd, mbstring, xdebug, etc.)  
- **phpMyAdmin:** 5.2.0 pre-installed  
- **Domain Whitelist:** Restrict access by domain name(s) – IP and localhost always allowed  
- **Logging:** Apache access and error logs are sent to `stdout`/`stderr` for easy viewing with `docker logs`  
- **Multi-arch:** Tested on `amd64`, `ARM64` (e.g., STB Armbian HG680P), and VM environments  

---

## 🧪 Tested On

- Virtual Machine (Ubuntu 20.04)  
- STB Armbian HG680P (ARM64)  
- Another ARM64 device  
- AMD64 (Intel NUC)  

---

## 📦 Included Packages

- Apache 2.4  
- MariaDB 10.6  
- PHP 7.4  
- phpMyAdmin 5.2.0  
- Composer  
- Xdebug (pre-configured)  
- Additional PHP extensions:  
  `ctype`, `curl`, `dom`, `gd`, `iconv`, `intl`, `json`, `mbstring`, `mcrypt`, `mysqli`, `opcache`, `pdo_mysql`, `phar`, `session`, `tokenizer`, `xml`, `zip`, `zlib`  

---

## 🚀 Quick Start

### 1. Pull or Build the Image

#### Option A: Pull from Docker Hub
```bash
docker pull rizkybs70/docker-lamp:latest
```

#### Option B: Build Locally
```bash
git clone https://github.com/rizkybs70/docker-lamp
cd docker-lamp
docker build -t docker-lamp .
```

### 2. Run the Container

```bash
docker run -d \
  --name=docker-lamp \
  -e MYSQL_ROOT_PASSWORD=yourpassword \          # Change this!
  -e ALLOWED_DOMAIN="example.com,test.org" \     # Optional: restrict to these domains
  -p 80:80 \
  -p 3306:3306 \
  -v /path/to/website:/var/www/localhost/htdocs \
  -v /path/to/mysql-data:/var/lib/mysql \
  --restart unless-stopped \
  rizkybs70/docker-lamp:latest
```

**Explanation of options:**
- `-e MYSQL_ROOT_PASSWORD=yourpassword` – Set the MySQL root password (required).  
- `-e ALLOWED_DOMAIN="example.com,test.org"` – Comma‑separated list of allowed domains (optional). If omitted or empty, **no domain restriction** is applied.  
- `-p 80:80` – Expose HTTP port.  
- `-p 3306:3306` – Expose MySQL port.  
- `-v /path/to/website:/var/www/localhost/htdocs` – Mount your website files.  
- `-v /path/to/mysql-data:/var/lib/mysql` – Persist MySQL data.  
- `--restart unless-stopped` – Auto‑restart policy.

---

## 🔐 Domain Whitelist Feature

The `ALLOWED_DOMAIN` environment variable lets you restrict HTTP access to specific domain names.  

- **Syntax:** Comma‑separated list, e.g. `"example.com,test.org"`. Spaces after commas are ignored.  
- **Wildcard:** Subdomains are **not** automatically allowed – you must list them explicitly. However, `www` variants are automatically permitted (e.g., if you allow `example.com`, both `example.com` and `www.example.com` are accepted).  
- **Always allowed:** Direct access via **IP address** (e.g., `http://192.168.1.100`) and **localhost** are always permitted, regardless of the whitelist.  
- **No restriction:** If `ALLOWED_DOMAIN` is not set or is empty, the container behaves like a normal LAMP stack – all domains are allowed.

**How it works:**  
The script generates an Apache `RewriteRule` that blocks requests with a `Host` header not matching the allowed domains (or IP/localhost). Blocked requests receive a **403 Forbidden** response.

---

## 🔍 Checking Logs

All Apache access and error logs are sent to the container’s `stdout`/`stderr`. View them with:

```bash
docker logs docker-lamp
```

Example access log line:
```
192.168.1.10 - - [03/Mar/2026:12:00:00 +0000] "GET /index.php HTTP/1.1" 200 1234 "-" "Mozilla/5.0 ..."
```

---

## 🛠️ Customization

### Change MySQL Root Password
Simply set `MYSQL_ROOT_PASSWORD` to your desired password.  
To generate a random password on each start, use `-e MYSQL_RANDOM_ROOT_PASSWORD=yes` – the generated password will be printed in the logs.

### Persistent Data
- Website files: mount a host directory to `/var/www/localhost/htdocs`
- MySQL data: mount a host directory to `/var/lib/mysql`

**Important:** Ensure the mounted directories have proper permissions. The container runs Apache as user `apache` (UID 100) and MySQL as user `mysql` (UID 100). If you encounter permission errors, adjust ownership:

```bash
sudo chown -R 100:100 /path/to/website
sudo chown -R 100:100 /path/to/mysql-data
```

---

## 🌐 Accessing Services

- **Web server:** `http://<host-ip>`  
- **phpMyAdmin:** `http://<host-ip>/phpmyadmin` (login with `root` and your MySQL password)  
- **MySQL from host:**  
  ```bash
  mysql -h <host-ip> -P 3306 -u root -p
  ```

---

## 🧹 Cleaning Up

After building the image, you can free disk space by removing unused build cache:

```bash
docker builder prune -f
```

---

## 👏 Acknowledgements

Original project by [j1cs/docker-lamp](https://github.com/j1cs/docker-lamp).  
Modifications for domain whitelist, multi‑arch support, and enhanced logging by [rizkybs70](https://github.com/rizkybs70).

---

## 📄 License

MIT
