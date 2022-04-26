#!/bin/bash
### Main Installer ###
INSTALLER_SCRIPT="VPSService-master/installer/main.sh"
. $INSTALLER_SCRIPT

# Logo
checkRoot
conlogo
connotice "Starting up script..."
sleep 3

### Pterodactyl Installer ###
# Basic questions
clear
coninfo "Basic questions for the user..."
sleep 1s

dbPass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
userPass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

while true; do
  echo -n "Your Email Address: "
  read -r userMail
  if [[ "$userMail" != "" ]]; then
    break
  fi
done

while true; do
  echo -n "Your Username: "
  read -r userUsername
  if [[ "$userUsername" != "" ]]; then
    break
  fi
done

while true; do
  echo -n "The URL for the panel (WITHOUT HTTP/HTTPS): "
  read -r userDomain
  if [[ "$userDomain" != "" ]]; then
    break
  fi
done

while true; do
  echo -n "Do you want to install a SSL certificate (Y/N): "
  read -r userSSL
  if [[ "$userSSL" != "" && "$userSSL" =~ ^[YyNn]$ ]]; then
    break
  fi
done

# Update and upgrade machine
clear
coninfo "Base setup..."
sleep 1s

apt-get -y update && apt-get -y upgrade
apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
apt-get -y update
apt-add-repository universe
apt-get -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server expect

# Installing composer
clear
coninfo "Installing composer..."
sleep 1s

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Setting up folders and files for pterodactyl
clear
coninfo "Setting up folders and files..."
sleep 1s

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
chown -R www-data:www-data /var/www/pterodactyl/*
cp .env.example .env

# Setting up mariadb user and database
clear
coninfo "Setting up mariadb user and database..."
sleep 1s

mysql -uroot << EOF
use mysql;
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$dbPass';
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Running php commands for application
clear
coninfo "Running artisan and composer commands for application..."
sleep 1s

export COMPOSER_ALLOW_SUPERUSER=1; composer install --no-dev --optimize-autoloader;
php artisan key:generate --force

# Environment configuration
clear
coninfo "Setting up environment configuration..."
sleep 1s

if [[ "$userSSL" =~ ^[Yy]$ ]]; then
  tempDomain="https://${userDomain}"
else
  tempDomain="http://${userDomain}"
fi

envSetup=$(expect -c "
set timeout 10
spawn php artisan p:environment:setup
expect \"Egg Author Email\"
send \"$userMail\r\"
expect \"Application URL\"
send \"$tempDomain\r\"
expect \"Application Timezone\"
send \"\r\"
expect \"Cache Driver\"
send \"\r\"
expect \"Session Driver\"
send \"\r\"
expect \"Queue Driver\"
send \"\r\"
expect \"Enable UI based settings editor? (yes/no)\"
send \"\r\"
expect eof
")
echo "$envSetup"

databaseSetup=$(expect -c "
set timeout 10
spawn php artisan p:environment:database
expect \"Database Host\"
send \"\r\"
expect \"Database Port\"
send \"\r\"
expect \"Database Name\"
send \"\r\"
expect \"Database Username\"
send \"\r\"
expect \"Database Password\"
send \"$dbPass\r\"
expect eof
")
echo "$databaseSetup"

echo
read -p "Do you want to do setup the mail environment? (Y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    php artisan p:environment:mail
fi

# Database setup
clear
coninfo "Running migrations and seeders..."
sleep 1s

php artisan migrate --seed --force

# Crontab configuration
clear
coninfo "Crontab configuration..."
sleep 1s

crontab -l > mycron
echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" >> mycron
crontab mycron
rm mycron

# Queue worker
clear
coninfo "Queue worker..."
sleep 1s

cat > /lib/systemd/system/pteroq.service << EOF
[Unit]
Description=Pterodactyl Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq.service

# Create first admin user
clear
coninfo "Create first administrator user..."
sleep 1s

createUser=$(expect -c "
set timeout 10
spawn php artisan p:user:make
expect \"Is this user an administrator? (yes/no)\"
send \"yes\r\"
expect \"Email Address\"
send \"$userMail\r\"
expect \"Username\"
send \"$userUsername\r\"
expect \"First Name\"
send \"FirstName\r\"
expect \"Last Name\"
send \"LastName\r\"
expect \"Password\"
send \"$userPass\r\"
expect eof
")
echo "$createUser"

# Setup webserver
clear
coninfo "Setup webserver..."
sleep 1s

systemctl stop apache2
apt-get remove -y apache2
systemctl start nginx

touch /etc/nginx/sites-available/pterodactyl.conf

if [[ $userSSL =~ ^[Yy]$ ]]; then
  apt-get install -y certbot
  apt-get install -y python3-certbot-nginx
  certbot certonly --nginx --non-interactive --agree-tos -m "$userMail" -d "$userDomain"

  cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server_tokens off;

server {
    listen 80;
    server_name $userDomain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $userDomain;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$userDomain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$userDomain/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.0-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

else
  cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name $userDomain;

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.0-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
fi

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx

# Finished
clear
echo "***********************************************************"
echo "                    SETUP COMPLETE"
echo "***********************************************************"
echo ""
echo " Domain: $userDomain"
echo " Pterodactyl user: $userUsername"
echo " Pterodactyl password: $userPass"
echo " MariaDB user: pterodactyl"
echo " MariaDB pass: $dbPass"
echo ""
echo "***********************************************************"
echo "          DO NOT LOSE AND KEEP SAFE THIS DATA"
echo "***********************************************************"