#!/bin/bash

# Install Some PPAs
sudo apt-add-repository ppa:ondrej/php -y

# Update Package Lists
sudo apt-get update -y

# Only php8.4-* here: unversioned php-* pulls Ondrej's default PHP (e.g. 8.5) and steals the `php` alternative
sudo apt-get install -y --allow-change-held-packages \
php8.4-imagick imagemagick

# PHP 8.4
sudo apt-get install -y --allow-change-held-packages \
php8.4 php8.4-bcmath php8.4-bz2 php8.4-cgi php8.4-cli php8.4-common php8.4-curl php8.4-dba php8.4-dev \
php8.4-enchant php8.4-fpm php8.4-gd php8.4-gmp php8.4-imap php8.4-interbase php8.4-intl php8.4-ldap \
php8.4-mbstring php8.4-mysql php8.4-odbc php8.4-opcache php8.4-pgsql php8.4-phpdbg php8.4-pspell php8.4-readline \
php8.4-snmp php8.4-soap php8.4-sqlite3 php8.4-sybase php8.4-tidy php8.4-xdebug php8.4-xml php8.4-xmlrpc php8.4-xsl \
php8.4-zip php8.4-memcached php8.4-redis

# Backup files we are about to modify
if [ ! -f /etc/php/8.4/cli/php.ini.bak ]; then
  sudo cp /etc/php/8.4/cli/php.ini /etc/php/8.4/cli/php.ini.bak
fi
if [ ! -f /etc/php/8.4/fpm/php.ini.bak ]; then
  sudo cp /etc/php/8.4/fpm/php.ini /etc/php/8.4/fpm/php.ini.bak
fi
if [ ! -f /etc/php/8.4/mods-available/xdebug.ini.bak ]; then
  sudo cp /etc/php/8.4/mods-available/xdebug.ini /etc/php/8.4/mods-available/xdebug.ini.bak
fi
if [ ! -f /etc/php/8.4/mods-available/opcache.ini.bak ]; then
  sudo cp /etc/php/8.4/mods-available/opcache.ini /etc/php/8.4/mods-available/opcache.ini.bak
fi
if [ ! -f /etc/php/8.4/fpm/pool.d/www.conf.bak ]; then
  sudo cp /etc/php/8.4/fpm/pool.d/www.conf /etc/php/8.4/fpm/pool.d/www.conf.bak
fi

# Configure php.ini for CLI
#sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/8.4/cli/php.ini
#sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php/8.4/cli/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = 1G/" /etc/php/8.4/cli/php.ini
sudo sed -i "s/;date.timezone.*/date.timezone = UTC+3/" /etc/php/8.4/cli/php.ini

# Configure Xdebug
#sudo bash -c 'echo "xdebug.mode = debug" >> /etc/php/8.4/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.discover_client_host = true" >> /etc/php/8.4/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.client_port = 9003" >> /etc/php/8.4/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.max_nesting_level = 512" >> /etc/php/8.4/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "opcache.revalidate_freq = 0" >> /etc/php/8.4/mods-available/opcache.ini'

# Configure php.ini for FPM
#sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/8.4/fpm/php.ini
#sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php/8.4/fpm/php.ini
#sudo sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/8.4/fpm/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = 1G/" /etc/php/8.4/fpm/php.ini
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/8.4/fpm/php.ini
sudo sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/8.4/fpm/php.ini
sudo sed -i "s/;date.timezone.*/date.timezone = UTC+3/" /etc/php/8.4/fpm/php.ini

sudo printf "[openssl]\n" | sudo tee -a /etc/php/8.4/fpm/php.ini
sudo printf "openssl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a /etc/php/8.4/fpm/php.ini
sudo printf "[curl]\n" | sudo tee -a /etc/php/8.4/fpm/php.ini
sudo printf "curl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a /etc/php/8.4/fpm/php.ini

# Default `php` / phar / phpdbg → 8.4 (otherwise apt may leave `php` on newest parallel install, e.g. 8.5)
if command -v update-alternatives >/dev/null 2>&1; then
  for alt in php phar phpdbg php-cgi phar.phar; do
    if [ -x "/usr/bin/${alt}8.4" ]; then
      sudo update-alternatives --set "$alt" "/usr/bin/${alt}8.4" 2>/dev/null || true
    fi
  done
fi
