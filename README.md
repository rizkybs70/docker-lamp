# Docker-Lamp
*This docker contain a LAMP stack installed from scratch*
source : https://github.com/j1cs/docker-lamp
Docker : https://github.com/rizkybs70/docker-lamp
_tested on Intel NUC OS Ubuntu 20.04 LTS, Armbian Debian 10 & 11_

### Include
* Base Alpine 3.12
* Apache2
* Mariadb
* PHP 7.3
* Phpmyadmin 5.1.1

### Images
| Architecture  | Images name |
| ------------- | ------------- |
| arm64 / armv8  | arm64  |
| amd64  | amd64  |


### Installation
amd64
```
docker run -d \
  --name=docker-lamp \
  -e MYSQL_ROOT_PASSWORD=sudirman \
  -p 80:80 \
  -p 3306:3306 \
  -v /root/lamp/website:/var/www/localhost/htdocs \
  -v /root/lamp/mysql:/var/lib/mysql \
  --restart unless-stopped \
  rizkybs70/docker-lamp:amd64
```
arm64
```
docker run -d \
  --name=docker-lamp \
  -e MYSQL_ROOT_PASSWORD=sudirman \
  -p 80:80 \
  -p 3306:3306 \
  -v /root/lamp/website:/var/www/localhost/htdocs \
  -v /root/lamp/mysql:/var/lib/mysql \
  --restart unless-stopped \
  rizkybs70/docker-lamp:arm64
```
### Build own images

```
git clone https://github.com/rizkybs70/docker-lamp
cd docker-lamp
docker build -t docker-lamp .
```
```
docker run -d \
  --name=docker-lamp \
  -e MYSQL_ROOT_PASSWORD=sudirman \
  -p 80:80 \
  -p 3306:3306 \
  -v /root/lamp/website:/var/www/localhost/htdocs \
  -v /root/lamp/mysql:/var/lib/mysql \
  --restart unless-stopped \
  docker-lamp
```

## Customize
Change password mysql
MYSQL_ROOT_PASSWORD=```sudirman``` 

Change directory data
-v ```/root/lamp/website```:/var/www/localhost/htdocs \
-v ```/root/lamp/mysql```:/var/lib/mysql

## To Access
http://ipserver/
Web Server port ```80```
Mysql ```3306```
phpmyadmin http://ipserver/phpmyadmin
password = sudirman


```
### Connect to MariaDB
To use this you need to install mysql/mariadb cli client
```
mysql -uroot -password -h 127.0.0.1
```
## Troubleshooting
### Forbidden error 403 
```
sudo chmod -Rf 755 /path/to/project
``` 
### Error activating InnoDB
If you get errors about activating InnoDB and you are on Windows or Mac, you
may be encountering [this
issue](https://github.com/docker-library/mariadb/issues/95) with using
host-mapped volumes for MariaDB. Work-around is to use a named volume
(persistent but not mapped), or [add/overwrite mysql config](https://github.com/docker-library/mariadb/issues/95#issuecomment-391587301) before entry.

### Missing libs
Please let me know or create a pull request

## Repos
https://hub.docker.com/r/j1cs/alpine-lamp  
https://github.com/j1cs/alpine-lamp

## Thanks to
https://github.com/j1cs/docker-lamp
