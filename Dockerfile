FROM ubuntu

MAINTAINER UltrafunkAmsterdam <leon@ultrafunk.nl>

WORKDIR /

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt -y update && \
    apt -y install software-properties-common wget lsb-release gnupg && \
    add-apt-repository -y ppa:ondrej/php && \
    add-apt-repository -y ppa:maxmind/ppa && \
    add-apt-repository -y ppa:nginx/stable && \
    wget -c https://repo.mysql.com//mysql-apt-config_0.8.13-1_all.deb && \
    dpkg -i mysql-apt-config_0.8.13-1_all.deb || true && \
    apt -y update || true && \
    apt -y install -f || true && \
    rm -f mysql-apt* && \
    mkdir /run/php && \
    apt -y install mysql-server && \
    apt -y install php7.4-fpm php7.4-gd php7.4-mysql php7.4-curl && \
    apt -y install nginx-extras && \
    apt-get clean && \
    find /var/log/* | grep -vE "(mysql|nginx|php)" | xargs rm -rf 

RUN \
    printf 'client_max_body_size 64M ; \
    server { \ 
    listen 80 default_server; \
    listen [::]:80 default_server; \
    root /var/www/; \
    index index.php index.html index.htm index.nginx-debian.html; \
    access_log /tmp/out.log; \
    error_log /tmp/err.log; \
    server_name _; \
    location / { \
            try_files $uri $uri/ =404; \ 
    } \
    location ~ \.php$ { \
        include /etc/nginx/snippets/fastcgi-php.conf; \
        fastcgi_pass unix:/run/php/php7.4-fpm.sock; \
    } \
    location ~ /\.ht { \
        deny all; \
    } \
}' >/etc/nginx/sites-enabled/default   \ 
  && sed -i "s|/var/log/php7.4-fpm.log|/tmp/out.log|g" /etc/php/7.4/fpm/php-fpm.conf  \
  && sed -i "s|/var/log/mysql/error.log|/tmp/err.log|g" /etc/mysql/mysql.conf.d/mysqld.cnf \
  && sed -i 's/max_execution_time = 30/max_execution_time = 120/g' /etc/php/7.4/fpm/php.ini  \
  && sed -i 's/post_max_size = 8M/post_max_size = 64M/g' /etc/php/7.4/fpm/php.ini \
  && sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 64M/g' /etc/php/7.4/fpm/php.ini 

RUN mkdir /conf  \
    && \
    ln -s /var/www / && \
    ln -s /etc/php/7.4/fpm/php-fpm.conf /conf/php-fpm.conf && \
    ln -s /etc/php/7.4/fpm/php.ini /conf/php.ini && \
    ln -s /etc/nginx/nginx.conf /conf/nginx.conf && \
    ln -s /etc/nginx/sites-enabled/default /conf/nginx-vhost.conf && \
    ln -s /etc/mysql/mysql.conf.d/mysqld.cnf /conf/mysqld.cnf 
     
RUN  wget https://wordpress.org/latest.tar.gz && tar xvfz latest.tar.gz -C /var/www --strip 1 && rm -rf latest.tar.gz && \
     sed -i 's|database_name_here|wordpress|g' www/wp-config-sample.php && \
     sed -i 's|username_here|wordpress|g' www/wp-config-sample.php && \
     sed -i 's|password_here|wordpress|g' www/wp-config-sample.php && \
     mv /var/www/wp-config-sample.php /var/www/wp-config.php && \
     chown -R www-data:www-data /var/www

RUN \
    mysqld --defaults-extra-file=/conf/mysqld.cnf --user=root & PID=$! && sleep 5   \
    && \  
    mysql -e  "use mysql; \
	       CREATE USER 'wordpress'@'localhost' IDENTIFIED BY 'wordpress';  \
	       CREATE DATABASE wordpress;  \
	       GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost'"  && \
   kill -2 $PID


RUN printf '#!/bin/bash \n \
	trap "cleanup" 1 2 3 6 9 14 15 \n \
	cleanup(){ \n \
	    echo "cleaning up" >> /tmp/out.log \n \
            sleep 2; \n \
	    kill -2 $(pidof mysqld nginx php-fpm7.4); \n \
	    exit 0 \n \
	} \n \
	mysqld --defaults-extra-file=/conf/mysqld.cnf --user=root & \n \
	php-fpm7.4 -R -c /etc/php/7.4/fpm/php.ini -y /etc/php/7.4/fpm/php-fpm.conf & \n \
        ln -sf /dev/stdout /tmp/out.log ;\n \
        ln -sf /dev/stderr /tmp/err.log ;\n \
        exec "$@" \
  ' > /entrypoint.sh && chmod +x /entrypoint.sh

VOLUME /conf 
VOLUME /www
VOLUME /var/lib
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
