#!/bin/bash

# Laravel Reverb: PHP pcntl only. Per-app `reverb:start` is defined in deploy/create_app.sh
# (path is always /home/<user>/deployments/current — not configurable here).

PHP_VER="${installs_php_version:-8.3}"

if ! sudo apt-get install -y "php${PHP_VER}-pcntl" 2>/dev/null; then
  if php -m 2>/dev/null | grep -qx 'pcntl'; then
    :
  elif command -v "php${PHP_VER}" >/dev/null 2>&1 && php${PHP_VER} -m 2>/dev/null | grep -qx 'pcntl'; then
    :
  else
    echo "Warning: php${PHP_VER}-pcntl not in apt and pcntl not loaded; install/enable pcntl for Reverb." >&2
  fi
fi
