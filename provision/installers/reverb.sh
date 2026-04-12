#!/bin/bash

# Laravel Reverb: pcntl (CLI) + Supervisor program.
# Proje tarafında: composer require laravel/reverb ve reverb yapılandırması gerekir.

PHP_VER="${installs_php_version:-8.3}"
APP_PATH="${installs_reverb_app_path:-/var/www/html}"

# pcntl: separate package on some releases; on others it is already built into php-cli
if ! sudo apt-get install -y "php${PHP_VER}-pcntl" 2>/dev/null; then
  if php -m 2>/dev/null | grep -qx 'pcntl'; then
    :
  elif command -v "php${PHP_VER}" >/dev/null 2>&1 && php${PHP_VER} -m 2>/dev/null | grep -qx 'pcntl'; then
    :
  else
    echo "Warning: php${PHP_VER}-pcntl not in apt and pcntl not loaded; install/enable pcntl for Reverb (Ondrej: php${PHP_VER}-pcntl)." >&2
  fi
fi

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
