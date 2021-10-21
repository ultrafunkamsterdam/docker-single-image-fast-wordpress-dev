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
    apt -y install php7.4-fpm php7.4-gd php7.4-mysql php7.4-curl php7.4-mbstring php7.4-xml php7.4-imagick && \
    apt -y install nginx-extras && \
    apt-get clean && \
    find /var/log/* | grep -vE "(mysql|nginx|php)" | xargs rm -rf 

RUN \
    printf ' \
    \
     upstream fcgi { \
        server unix:/run/php/php7.4-fpm.sock max_fails=3 fail_timeout=3s; \
        keepalive 16; \
    } \
    sendfile on; \
    keepalive_timeout 65; \
    server_tokens off; \
    fastcgi_buffers 256 4k; \
    client_max_body_size 64M ; \
    \
    fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=WORDPRESS:100m inactive=60m; \
    fastcgi_cache_key "$scheme$request_method$host$request_uri"; \
    fastcgi_cache_use_stale error timeout invalid_header http_500; \
    fastcgi_ignore_headers Cache-Control Expires Set-Cookie; \
   
    server { \ 
    listen 80 default_server; \
    listen [::]:80 default_server; \
    root /var/www/; \
    index index.php index.html index.htm index.nginx-debian.html; \
    access_log /tmp/out.log; \
    error_log /tmp/err.log; \
    server_name _; \
     set $skip_cache 0; \
  \
    # POST requests and urls with a query string should always go to PHP \
    if ($request_method = POST) { \
        set $skip_cache 1; \
    }   \
   
\
    # Don't cache uris containing the following segments \
    if ($request_uri ~* "/wp-admin/|/xmlrpc.php|wp-.*.php|/feed/|index.php|sitemap(_index)?.xml") { \
        set $skip_cache 1; \
    }   \
\
    # Don't use the cache for logged in users or recent commenters '
    if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") { \
        set $skip_cache 1; \
    } \
\
    location / { \
            try_files $uri $uri/ /index.php?$args ; \ 
    } \
    location ~ \.php$ { \
         include fastcgi_params; \
         # include /etc/nginx/snippets/fastcgi-php.conf; \
         fastcgi_pass unix:/run/php/php7.4-fpm.sock; \
	 fastcgi_cache_bypass $skip_cache; \
         fastcgi_no_cache $skip_cache; \
	 fastcgi_cache WORDPRESS; \
         fastcgi_cache_valid  60m; \
    } \
    location ~ /purge(/.*) { \
        fastcgi_cache_purge WORDPRESS "$scheme$request_method$host$1";  \
    }   \
\
    location ~* ^.+\.(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ { \
        access_log off; log_not_found off; expires max;  \
    }  \
\
    location = /robots.txt { access_log off; log_not_found off; } \
    location ~ /\. { deny  all; access_log off; log_not_found off; } \
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
