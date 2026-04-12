#!/bin/bash

# Laravel Reverb: pcntl (CLI) + Supervisor program.
# Proje tarafında: composer require laravel/reverb ve reverb yapılandırması gerekir.

PHP_VER="${installs_php_version:-8.3}"
APP_PATH="${installs_reverb_app_path:-/var/www/html}"

sudo apt-get install -y "php${PHP_VER}-pcntl"

LOG_FILE=/var/log/laravel-reverb.log
sudo touch "$LOG_FILE"
sudo chown www-data:www-data "$LOG_FILE"

sudo tee /etc/supervisor/conf.d/laravel-reverb.conf > /dev/null <<EOF
[program:laravel-reverb]
process_name=%(program_name)s
command=/usr/bin/php ${APP_PATH}/artisan reverb:start
directory=${APP_PATH}
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=${LOG_FILE}
stopwaitsecs=3600
EOF

sudo supervisorctl reread
sudo supervisorctl update
