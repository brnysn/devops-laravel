#!/bin/bash
set -euo pipefail

TARGET_PHP_VERSION="8.4"
ACTIVE_PHP_VERSION="$TARGET_PHP_VERSION"
FPM_INI=""
CLI_INI=""

apt_retry() {
  local max_attempts=40
  local sleep_seconds=5
  local attempt=1
  local output=""

  while [ "$attempt" -le "$max_attempts" ]; do
    if output=$("$@" 2>&1); then
      [ -n "$output" ] && echo "$output"
      return 0
    fi

    echo "$output" >&2
    if [[ "$output" == *"Could not get lock"* || "$output" == *"Unable to lock directory"* ]]; then
      sleep "$sleep_seconds"
      attempt=$((attempt + 1))
      continue
    fi

    return 1
  done

  echo "ERROR: apt/dpkg lock held for too long; aborting." >&2
  return 1
}

apt_install() {
  apt_retry sudo apt-get -o DPkg::Lock::Timeout=120 install -y --allow-change-held-packages "$@"
}

ondrej_release_exists() {
  local codename
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  curl -fsSI "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${codename}/Release" >/dev/null 2>&1
}

install_requested_version() {
  apt_install \
  "php${TARGET_PHP_VERSION}-imagick" imagemagick

  apt_install \
  "php${TARGET_PHP_VERSION}" "php${TARGET_PHP_VERSION}-bcmath" "php${TARGET_PHP_VERSION}-bz2" "php${TARGET_PHP_VERSION}-cgi" "php${TARGET_PHP_VERSION}-cli" "php${TARGET_PHP_VERSION}-common" "php${TARGET_PHP_VERSION}-curl" "php${TARGET_PHP_VERSION}-dba" "php${TARGET_PHP_VERSION}-dev" \
  "php${TARGET_PHP_VERSION}-enchant" "php${TARGET_PHP_VERSION}-fpm" "php${TARGET_PHP_VERSION}-gd" "php${TARGET_PHP_VERSION}-gmp" "php${TARGET_PHP_VERSION}-imap" "php${TARGET_PHP_VERSION}-interbase" "php${TARGET_PHP_VERSION}-intl" "php${TARGET_PHP_VERSION}-ldap" \
  "php${TARGET_PHP_VERSION}-mbstring" "php${TARGET_PHP_VERSION}-mysql" "php${TARGET_PHP_VERSION}-odbc" "php${TARGET_PHP_VERSION}-opcache" "php${TARGET_PHP_VERSION}-pgsql" "php${TARGET_PHP_VERSION}-phpdbg" "php${TARGET_PHP_VERSION}-pspell" "php${TARGET_PHP_VERSION}-readline" \
  "php${TARGET_PHP_VERSION}-snmp" "php${TARGET_PHP_VERSION}-soap" "php${TARGET_PHP_VERSION}-sqlite3" "php${TARGET_PHP_VERSION}-sybase" "php${TARGET_PHP_VERSION}-tidy" "php${TARGET_PHP_VERSION}-xdebug" "php${TARGET_PHP_VERSION}-xml" "php${TARGET_PHP_VERSION}-xmlrpc" "php${TARGET_PHP_VERSION}-xsl" \
  "php${TARGET_PHP_VERSION}-zip" "php${TARGET_PHP_VERSION}-memcached" "php${TARGET_PHP_VERSION}-redis"
}

install_distro_php_fallback() {
  echo "Requested PHP ${TARGET_PHP_VERSION} unavailable on this Ubuntu suite; installing distro PHP instead." >&2
  apt_install php php-cli php-fpm imagemagick
  for pkg in php-bcmath php-bz2 php-curl php-dba php-dev php-enchant php-gd php-gmp php-imap php-intl php-ldap \
    php-mbstring php-mysql php-odbc php-opcache php-pgsql php-phpdbg php-pspell php-readline php-snmp php-soap php-sqlite3 php-tidy \
    php-xml php-xsl php-zip php-imagick php-memcached php-redis; do
    apt_install "$pkg" 2>/dev/null || true
  done
}

# Install Some PPAs (when supported by current distro)
if ondrej_release_exists; then
  sudo apt-add-repository ppa:ondrej/php -y
fi

# Update Package Lists
if ! apt_retry sudo apt-get -o DPkg::Lock::Timeout=120 update -y; then
  apt_retry sudo apt-get -o DPkg::Lock::Timeout=120 -o Acquire::ForceIPv4=true update -y
fi

if ! install_requested_version; then
  install_distro_php_fallback
fi

ACTIVE_PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
if [ -z "$ACTIVE_PHP_VERSION" ]; then
  echo "ERROR: PHP installation failed (no php binary found)." >&2
  exit 1
fi

CLI_INI="/etc/php/${ACTIVE_PHP_VERSION}/cli/php.ini"
FPM_INI="/etc/php/${ACTIVE_PHP_VERSION}/fpm/php.ini"

# Backup files we are about to modify
if [ -f "$CLI_INI" ] && [ ! -f "${CLI_INI}.bak" ]; then
  sudo cp "$CLI_INI" "${CLI_INI}.bak"
fi
if [ -f "$FPM_INI" ] && [ ! -f "${FPM_INI}.bak" ]; then
  sudo cp "$FPM_INI" "${FPM_INI}.bak"
fi
if [ -f "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/xdebug.ini" ] && [ ! -f "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/xdebug.ini.bak" ]; then
  sudo cp "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/xdebug.ini" "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/xdebug.ini.bak"
fi
if [ -f "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/opcache.ini" ] && [ ! -f "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/opcache.ini.bak" ]; then
  sudo cp "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/opcache.ini" "/etc/php/${ACTIVE_PHP_VERSION}/mods-available/opcache.ini.bak"
fi
if [ -f "/etc/php/${ACTIVE_PHP_VERSION}/fpm/pool.d/www.conf" ] && [ ! -f "/etc/php/${ACTIVE_PHP_VERSION}/fpm/pool.d/www.conf.bak" ]; then
  sudo cp "/etc/php/${ACTIVE_PHP_VERSION}/fpm/pool.d/www.conf" "/etc/php/${ACTIVE_PHP_VERSION}/fpm/pool.d/www.conf.bak"
fi

# Configure php.ini for CLI
#sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/8.4/cli/php.ini
#sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php/8.4/cli/php.ini
if [ -f "$CLI_INI" ]; then
  sudo sed -i "s/memory_limit = .*/memory_limit = 1G/" "$CLI_INI"
  sudo sed -i "s|;date.timezone.*|date.timezone = UTC+3|" "$CLI_INI"
fi

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
if [ -f "$FPM_INI" ]; then
  sudo sed -i "s/memory_limit = .*/memory_limit = 1G/" "$FPM_INI"
  sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" "$FPM_INI"
  sudo sed -i "s/post_max_size = .*/post_max_size = 100M/" "$FPM_INI"
  sudo sed -i "s|;date.timezone.*|date.timezone = UTC+3|" "$FPM_INI"

  if ! sudo rg -q "^\[openssl\]$" "$FPM_INI"; then
    sudo printf "[openssl]\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
  if ! sudo rg -q "^openssl\.cainfo = /etc/ssl/certs/ca-certificates\.crt$" "$FPM_INI"; then
    sudo printf "openssl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
  if ! sudo rg -q "^\[curl\]$" "$FPM_INI"; then
    sudo printf "[curl]\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
  if ! sudo rg -q "^curl\.cainfo = /etc/ssl/certs/ca-certificates\.crt$" "$FPM_INI"; then
    sudo printf "curl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
fi

# Default `php` / phar / phpdbg → active installed version
if command -v update-alternatives >/dev/null 2>&1; then
  for alt in php phar phpdbg php-cgi phar.phar; do
    if [ -x "/usr/bin/${alt}${ACTIVE_PHP_VERSION}" ]; then
      sudo update-alternatives --set "$alt" "/usr/bin/${alt}${ACTIVE_PHP_VERSION}" 2>/dev/null || true
    fi
  done
fi
