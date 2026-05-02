#!/bin/bash

php_install_fail() {
  error "PHP 8.3 install failed: $1"
}

php83_install_ok=true

# Install Some PPAs
if ! sudo apt-add-repository ppa:ondrej/php -y; then
  php83_install_ok=false
  php_install_fail "unable to add ppa:ondrej/php"
fi

# Update Package Lists
if ! sudo apt-get update -y; then
  php83_install_ok=false
  php_install_fail "apt-get update failed after adding ondrej/php"
fi

php83_candidate="$(apt-cache policy php8.3-cli | awk '/Candidate:/ {print $2}')"
if [ -z "$php83_candidate" ] || [ "$php83_candidate" = "(none)" ]; then
  php83_install_ok=false
  ubuntu_codename=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    ubuntu_codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  fi
  php_install_fail "php8.3-cli has no install candidate (codename: ${ubuntu_codename:-unknown}). Will install distro PHP instead."
fi

if $php83_install_ok; then
  # Only php8.3-* here: unversioned php-* pulls Ondrej's default PHP (e.g. 8.5) and steals the `php` alternative
  if ! sudo apt-get install -y --allow-change-held-packages \
  php8.3-imagick imagemagick; then
    php83_install_ok=false
    php_install_fail "failed installing php8.3-imagick prerequisites"
  fi
fi

if $php83_install_ok; then
  # PHP 8.3
  if ! sudo apt-get install -y --allow-change-held-packages \
  php8.3 php8.3-bcmath php8.3-bz2 php8.3-cgi php8.3-cli php8.3-common php8.3-curl php8.3-dba php8.3-dev \
  php8.3-enchant php8.3-fpm php8.3-gd php8.3-gmp php8.3-imap php8.3-interbase php8.3-intl php8.3-ldap \
  php8.3-mbstring php8.3-mysql php8.3-odbc php8.3-opcache php8.3-pgsql php8.3-phpdbg php8.3-pspell php8.3-readline \
  php8.3-snmp php8.3-soap php8.3-sqlite3 php8.3-sybase php8.3-tidy php8.3-xdebug php8.3-xml php8.3-xmlrpc php8.3-xsl \
  php8.3-zip php8.3-memcached php8.3-redis; then
    php83_install_ok=false
    php_install_fail "failed installing php8.3 packages"
  fi
fi

if $php83_install_ok && { [ ! -x /usr/bin/php8.3 ] || [ ! -f /etc/php/8.3/cli/php.ini ] || [ ! -f /etc/php/8.3/fpm/php.ini ]; }; then
  php83_install_ok=false
  php_install_fail "php8.3 binaries/config files were not created"
fi

if ! $php83_install_ok; then
  status "Falling back to distro PHP packages"
  # Install core PHP first, then optional extensions individually so one missing package does not abort everything.
  if ! sudo apt-get install -y --allow-change-held-packages php php-cli php-common php-fpm; then
    error "Failed to install fallback core PHP packages"
    return 1
  fi

  fallback_extensions=(
    php-curl php-mbstring php-xml php-zip php-bcmath php-intl php-mysql php-sqlite3
    php-gd php-soap php-readline php-opcache php-redis php-imagick imagemagick
  )
  for pkg in "${fallback_extensions[@]}"; do
    if ! sudo apt-get install -y --allow-change-held-packages "$pkg"; then
      status "Skipping unavailable fallback package: $pkg"
    fi
  done
fi

PHP_ACTIVE_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
if [ -z "$PHP_ACTIVE_VERSION" ]; then
  error "PHP is still not available after install attempts"
  return 1
fi

PHP_ETC_DIR="/etc/php/${PHP_ACTIVE_VERSION}"
CLI_INI="${PHP_ETC_DIR}/cli/php.ini"
FPM_INI="${PHP_ETC_DIR}/fpm/php.ini"
XDEBUG_INI="${PHP_ETC_DIR}/mods-available/xdebug.ini"
OPCACHE_INI="${PHP_ETC_DIR}/mods-available/opcache.ini"
FPM_POOL="${PHP_ETC_DIR}/fpm/pool.d/www.conf"

# Backup files we are about to modify
if [ -f "$CLI_INI" ] && [ ! -f "${CLI_INI}.bak" ]; then
  sudo cp "$CLI_INI" "${CLI_INI}.bak"
fi
if [ -f "$FPM_INI" ] && [ ! -f "${FPM_INI}.bak" ]; then
  sudo cp "$FPM_INI" "${FPM_INI}.bak"
fi
if [ -f "$XDEBUG_INI" ] && [ ! -f "${XDEBUG_INI}.bak" ]; then
  sudo cp "$XDEBUG_INI" "${XDEBUG_INI}.bak"
fi
if [ -f "$OPCACHE_INI" ] && [ ! -f "${OPCACHE_INI}.bak" ]; then
  sudo cp "$OPCACHE_INI" "${OPCACHE_INI}.bak"
fi
if [ -f "$FPM_POOL" ] && [ ! -f "${FPM_POOL}.bak" ]; then
  sudo cp "$FPM_POOL" "${FPM_POOL}.bak"
fi

# Configure php.ini for CLI
#sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" "$CLI_INI"
#sudo sed -i "s/display_errors = .*/display_errors = On/" "$CLI_INI"
if [ -f "$CLI_INI" ]; then
  sudo sed -i "s/memory_limit = .*/memory_limit = 1024M/" "$CLI_INI"
  sudo sed -i "s/;date.timezone.*/date.timezone = UTC+3/" "$CLI_INI"
fi

# Configure Xdebug
#sudo bash -c 'echo "xdebug.mode = debug" >> /etc/php/8.3/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.discover_client_host = true" >> /etc/php/8.3/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.client_port = 9003" >> /etc/php/8.3/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "xdebug.max_nesting_level = 512" >> /etc/php/8.3/mods-available/xdebug.ini'
#sudo bash -c 'sudo echo "opcache.revalidate_freq = 0" >> /etc/php/8.3/mods-available/opcache.ini'

# Configure php.ini for FPM
#sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" "$FPM_INI"
#sudo sed -i "s/display_errors = .*/display_errors = On/" "$FPM_INI"
#sudo sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" "$FPM_INI"
if [ -f "$FPM_INI" ]; then
  sudo sed -i "s/memory_limit = .*/memory_limit = 1024M/" "$FPM_INI"
  sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" "$FPM_INI"
  sudo sed -i "s/post_max_size = .*/post_max_size = 100M/" "$FPM_INI"
  sudo sed -i "s/;date.timezone.*/date.timezone = UTC+3/" "$FPM_INI"

  if ! rg -q "^\[openssl\]" "$FPM_INI"; then
    sudo printf "[openssl]\n" | sudo tee -a "$FPM_INI" >/dev/null
    sudo printf "openssl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
  if ! rg -q "^\[curl\]" "$FPM_INI"; then
    sudo printf "[curl]\n" | sudo tee -a "$FPM_INI" >/dev/null
    sudo printf "curl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | sudo tee -a "$FPM_INI" >/dev/null
  fi
fi

# Default `php` / phar / phpdbg → installed active version
if command -v update-alternatives >/dev/null 2>&1; then
  for alt in php phar phpdbg php-cgi phar.phar; do
    if [ -x "/usr/bin/${alt}${PHP_ACTIVE_VERSION}" ]; then
      sudo update-alternatives --set "$alt" "/usr/bin/${alt}${PHP_ACTIVE_VERSION}" 2>/dev/null || true
    fi
  done
fi
