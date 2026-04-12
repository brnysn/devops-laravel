#!/bin/bash

# Save current directory and cd into script path
initial_working_directory=$(pwd)
parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd "$parent_path"

# Load the helpers
source $parent_path/../common/helpers.sh

title "Create devops shell aliases"
# If provision was started with sudo, aliases must go to the real login user (~/.bash_aliases), not root's.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  sudo -H -u "$SUDO_USER" bash "$parent_path/../common/create_aliases.sh"
elif [ "$(id -u)" -eq 0 ] && id ubuntu &>/dev/null; then
  sudo -H -u ubuntu bash "$parent_path/../common/create_aliases.sh"
else
  bash "$parent_path/../common/create_aliases.sh"
fi

# Load the config file (yaml)
source $parent_path/../common/parse_yaml.sh
eval $(parse_yaml $parent_path/../config.yml)

# Non-interactive apt + needrestart (avoids "Newer kernel available" whiptail over SSH)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFOLD=1

title "Update Package List"
sudo -E apt-get update -y

title "Configure needrestart (no kernel reboot dialog)"
sudo -E apt-get install -y needrestart 2>/dev/null || true
if [ -f /etc/needrestart/needrestart.conf ]; then
  sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
  sudo sed -i "s/^\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
  sudo sed -i "s/^#\$nrconf{kernelhints} = 1/\$nrconf{kernelhints} = 0/" /etc/needrestart/needrestart.conf
  sudo sed -i "s/^\$nrconf{kernelhints} = 1;/\$nrconf{kernelhints} = 0;/" /etc/needrestart/needrestart.conf
  sudo sed -i "s/^#\$nrconf{ui} = 'i';/\$nrconf{ui} = 'a';/" /etc/needrestart/needrestart.conf
  sudo sed -i "s/^\$nrconf{ui} = 'i';/\$nrconf{ui} = 'a';/" /etc/needrestart/needrestart.conf
fi

title "Upgrade Packages"
sudo -E apt-get upgrade -y

# Install Some Basic Packages....TODO: FILTER THROUGH THESE
title "Install Basic Packages"
sudo -E apt-get install -y software-properties-common curl gnupg debian-keyring debian-archive-keyring apt-transport-https \
ca-certificates build-essential dos2unix gcc git git-lfs libmcrypt4 libpcre3-dev libpng-dev chrony make pv \
python3-pip re2c supervisor unattended-upgrades whois vim cifs-utils bash-completion zsh zip unzip expect

# Create Swap Space
title "Create Swap Space"
case $installs_swapspace in
  [yY][eE][sS]|[yY])
    if [ -f /swapfile ]; then
      status "swapfile already exists"
    else
      total_ram=$(free -m | grep Mem: | awk '{print $2}')
      sudo fallocate -l ${total_ram}M /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile
      status "swapfile created"
    fi;;
  *)
    status "not creating swap space";;
esac

title "Install Nginx"
case $installs_nginx in
  [yY][eE][sS]|[yY])
    source ./installers/nginx.sh
    status "nginx installed";;
  *)
    status "not installing nginx";;
esac

title "Install PHP Version"
case $installs_php_install in
  [yY][eE][sS]|[yY])
    source "./installers/php${installs_php_version}.sh"
    status "php$installs_php_version installed";;
  *)
    status "not installing php$installs_php_version";;
esac

title "Install Composer"
case $installs_php_composer in
  [yY][eE][sS]|[yY])
  source ./installers/composer.sh
  status "composer installed";;
  *)
  status "not installing composer";;
esac

title "Install Node and NPM"
case $installs_node_and_npm in
  [yY][eE][sS]|[yY])
  source ./installers/node.sh
  status "node installed";;
  *)
  status "not installing node";;
esac

title "Install Redis"
case $installs_redis in
  [yY][eE][sS]|[yY])
  source ./installers/redis.sh
  status "redis installed";;
  *)
  status "not installing redis";;
esac

title "Configure Laravel Reverb"
reverb_config_value="${installs_reverb:-${installs_reverb_install:-no}}"
case $reverb_config_value in
  [yY][eE][sS]|[yY])
    source ./installers/reverb.sh
    status "reverb runtime prerequisites configured";;
  *)
    status "not configuring reverb";;
esac

title "Install Typesense"
case $installs_typesense_install in
  [yY][eE][sS]|[yY])
    source ./installers/typesense.sh
    status "typesense installed";;
  *)
    status "not installing typesense";;
esac

title "Install SQLite"
case $installs_sqlite in
  [yY][eE][sS]|[yY])
    source ./installers/sqlite.sh
    status "sqlite installed";;
  *)
    status "not installing sqlite";;
esac

title "Install MySQL"
case $installs_database_mysql in
  [yY][eE][sS]|[yY])
  source ./installers/mysql.sh
  status "mysql installed";;
  *)
  status "not installing mysql";;
esac

title "Install MariaDB"
case $installs_database_mariadb in
  [yY][eE][sS]|[yY])
  source ./installers/mariadb.sh
  status "mariadb installed";;
  *)
  status "not installing mariadb";;
esac

title "Install Certbot (LetsEncrypt)"
case $installs_certbot in
  [yY][eE][sS]|[yY])
  source ./installers/certbot.sh
  status "certbot installed";;
  *)
  status "not installing certbot";;
esac

# Force Locale
#echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale
#locale-gen en_US.UTF-8

# Set My Timezone
#sudo ln -sf /usr/share/zoneinfo/UTC /etc/localtime

title "Install apache"
case $installs_apache in
  [yY][eE][sS]|[yY])
  source ./installers/apache.sh
  status "apache installed";;
  *)
  status "not installing apache";;
esac

title "Install memcache"
case $installs_memcache in
  [yY][eE][sS]|[yY])
  source ./installers/memcache.sh
  status "memcache installed";;
  *)
  status "not installing memcache";;
esac

title "Install beanstalk"
case $installs_beanstalk in
  [yY][eE][sS]|[yY])
  source ./installers/beanstalk.sh
  status "beanstalk installed";;
  *)
  status "not installing beanstalk";;
esac

title "Install mailhog"
case $installs_mailhog in
  [yY][eE][sS]|[yY])
  source ./installers/mailhog.sh
  status "mailhog installed";;
  *)
  status "not installing mailhog";;
esac

title "Install ngrok"
case $installs_ngrok in
  [yY][eE][sS]|[yY])
  source ./installers/ngrok.sh
  status "ngrok installed";;
  *)
  status "not installing ngrok";;
esac

title "Install postfix"
case $installs_postfix in
  [yY][eE][sS]|[yY])
  source ./installers/postfix.sh
  status "postfix installed";;
  *)
  status "not installing postfix";;
esac

# One last upgrade check
title "One Last Upgrade Check"
sudo -E apt-get upgrade -y

# Clean Up
title "Clean Up"
sudo -E apt-get -y autoremove
sudo -E apt-get -y clean

# Re-pin default `php` after final upgrade (parallel PHP installs may reset alternatives)
case $installs_php_install in
  [yY][eE][sS]|[yY])
    PV="${installs_php_version}"
    if [ -n "$PV" ] && [ -x "/usr/bin/php${PV}" ]; then
      for alt in php phar phpdbg php-cgi phar.phar; do
        if [ -x "/usr/bin/${alt}${PV}" ]; then
          sudo update-alternatives --set "$alt" "/usr/bin/${alt}${PV}" 2>/dev/null || true
        fi
      done
    fi
    ;;
esac

title "Status Report"
report_binary_version() {
  local label="$1"
  local binary="$2"
  shift 2

  if ! command -v "$binary" >/dev/null 2>&1; then
    status "$label: (not installed)"
    return 0
  fi

  local output
  local exit_code
  output=$(timeout 15s "$binary" "$@" 2>&1)
  exit_code=$?

  case $exit_code in
    0)
      status "$label: $output"
      ;;
    124)
      status "$label: (timed out)"
      ;;
    *)
      status "$label: (error running $binary)"
      ;;
  esac
}

report_shell_output() {
  local label="$1"
  shift

  local output
  local exit_code
  output=$(timeout 15s "$@" 2>&1)
  exit_code=$?

  case $exit_code in
    0)
      status "$label: $output"
      ;;
    124)
      status "$label: (timed out)"
      ;;
    *)
      status "$label: (error)"
      ;;
  esac
}

report_binary_version "Nginx Version" nginx -v

PHP_REPORT_BIN=php
case $installs_php_install in
  [yY][eE][sS]|[yY])
    if command -v "php${installs_php_version}" >/dev/null 2>&1; then
      PHP_REPORT_BIN="php${installs_php_version}"
    fi
    ;;
esac
report_binary_version "PHP VERSION ($PHP_REPORT_BIN)" "$PHP_REPORT_BIN" -r 'echo PHP_VERSION;'
report_binary_version "Composer Version" composer -V
report_binary_version "Node Version" node -v
report_binary_version "NPM Version" npm -v
report_binary_version "Redis Version" redis-cli -v
report_binary_version "SQLite Version" sqlite3 --version
report_binary_version "MySQL Version" mysql -V
report_binary_version "Certbot Version" certbot --version
report_shell_output "Swap Space" swapon --show

# Return back to the original directory
cd $initial_working_directory
