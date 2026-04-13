#!/bin/bash

# Expecting one argument that is the app name to create
my_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
if [ $# -eq 0 ]; then
  echo "No app specified!"
  existing_apps=$(ls $my_path/../apps/ | sed -e 's|\.[^.]*$||')
  echo "Try one of these applications:"
  echo "$existing_apps"
  exit 1
fi

# Application to create is argument #1
app_name="$1"

# Save current directory and cd into script path
initial_working_directory=$(pwd)
my_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd "$my_path"

# Load common
source $my_path/../common/load_common.sh

# Reverb (config.yml installs.reverb): port stable per username; nginx + .env + daemon when enabled
reverb_enabled=0
reverb_config_value="${installs_reverb:-${installs_reverb_install:-no}}"
case "${reverb_config_value:-}" in
  [yY][eE][sS]|[yY]) reverb_enabled=1 ;;
esac
reverb_listen_port=$(( 9080 + $(printf '%s' "$username" | cksum | awk '{print $1 % 1000}') ))

typesense_enabled=0
case "${installs_typesense_install:-}" in
  [yY][eE][sS]|[yY]) typesense_enabled=1 ;;
esac
typesense_api_key="${installs_typesense_api_key:-change-me-typesense-key}"
typesense_host="${installs_typesense_api_address:-127.0.0.1}"
typesense_port="${installs_typesense_api_port:-8108}"
typesense_protocol="${installs_typesense_protocol:-http}"
env_file="$deploy_directory/symlinks/.env"

upsert_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped_value

  if [ ! -f "$file" ]; then
    return 1
  fi

  if grep -q "^${key}=" "$file"; then
    escaped_value=$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

get_env_value() {
  local file="$1"
  local key="$2"
  local value

  value=$(grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2-)
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

derive_public_app_endpoint() {
  local file="$1"
  local app_url
  local parsed

  app_url=$(get_env_value "$file" APP_URL)
  parsed=$(php -r '
    $url = $argv[1] ?? "";
    $defaultPort = $argv[2] ?? "80";
    $parts = parse_url($url ?: "");

    $scheme = $parts["scheme"] ?? "http";
    $host = $parts["host"] ?? "localhost";
    $port = $parts["port"] ?? $defaultPort;

    echo $scheme, PHP_EOL, $host, PHP_EOL, $port, PHP_EOL;
  ' "$app_url" "$app_port" 2>/dev/null)

  app_public_scheme=$(printf '%s\n' "$parsed" | sed -n '1p')
  app_public_host=$(printf '%s\n' "$parsed" | sed -n '2p')
  app_public_port=$(printf '%s\n' "$parsed" | sed -n '3p')

  if [ -z "$app_public_scheme" ]; then
    app_public_scheme="http"
  fi
  if [ -z "$app_public_host" ]; then
    app_public_host="localhost"
  fi
  if [ -z "$app_public_port" ]; then
    app_public_port="$app_port"
  fi
}

configure_typesense_env() {
  if [ "$typesense_enabled" -eq 0 ] || [ ! -f "$env_file" ]; then
    return 0
  fi

  upsert_env_value "$env_file" "TYPESENSE_API_KEY" "$typesense_api_key"
  upsert_env_value "$env_file" "TYPESENSE_HOST" "$typesense_host"
  upsert_env_value "$env_file" "TYPESENSE_PORT" "$typesense_port"
  upsert_env_value "$env_file" "TYPESENSE_PATH" ""
  upsert_env_value "$env_file" "TYPESENSE_PROTOCOL" "$typesense_protocol"
  chown "$username:$username" "$env_file"
}

configure_reverb_env() {
  if [ "$reverb_enabled" -eq 0 ] || [ ! -f "$env_file" ]; then
    return 0
  fi

  derive_public_app_endpoint "$env_file"

  upsert_env_value "$env_file" "BROADCAST_CONNECTION" "reverb"
  upsert_env_value "$env_file" "REVERB_HOST" "$app_public_host"
  upsert_env_value "$env_file" "REVERB_PORT" "$app_public_port"
  upsert_env_value "$env_file" "REVERB_SCHEME" "$app_public_scheme"
  upsert_env_value "$env_file" "REVERB_SERVER_HOST" "127.0.0.1"
  upsert_env_value "$env_file" "REVERB_SERVER_PORT" "$reverb_listen_port"
  upsert_env_value "$env_file" "VITE_REVERB_APP_KEY" '"${REVERB_APP_KEY}"'
  upsert_env_value "$env_file" "VITE_REVERB_HOST" '"${REVERB_HOST}"'
  upsert_env_value "$env_file" "VITE_REVERB_PORT" '"${REVERB_PORT}"'
  upsert_env_value "$env_file" "VITE_REVERB_SCHEME" '"${REVERB_SCHEME}"'
  chown "$username:$username" "$env_file"
}

reverb_declared_in_composer() {
  [ -f "$deploy_directory/current/composer.json" ] && grep -q '"laravel/reverb"' "$deploy_directory/current/composer.json"
}

reverb_installed_for_app() {
  if [ ! -f "$deploy_directory/current/composer.json" ]; then
    return 1
  fi

  sudo -u "$username" bash -lc "cd $deploy_directory/current && composer show laravel/reverb --no-interaction >/dev/null 2>&1"
}

reverb_declared=0
reverb_installed=0

# Guard against overwriting and existing user
title "Create Deployment User: $username"
if id "$username" >/dev/null 2>&1; then
  error "This user already exists. Username: $username"
else
  # Create the deployment user
  sudo adduser --gecos "" --disabled-password $username
  sudo chpasswd <<<"$username:$password"

  # Create the Github Deployment Keys
  title "Creating Github Deployment Keys"
  sudo su - $username <<EOF
# Create the Github keys
ssh-keygen -f ~/.ssh/github_rsa -t rsa -N ""
cat <<EOT >> ~/.ssh/config
Host github.com
        IdentityFile ~/.ssh/github_rsa
        IdentitiesOnly yes
EOT
chmod 700 ~/.ssh
chmod 600 ~/.ssh/*

echo "----------------------COPY PUB KEY TO GITHUB DEPLOYMENT KEYS---------------------"
cat < ~/.ssh/github_rsa.pub
echo "---------------------------------------------------------------------------------"

# End session
exit
EOF

  title "Adding www-data to user group: $username"
  sudo usermod -a -G $username www-data

  title "Creating Laravel .env File"
  sudo su - $username <<EOF
if [ ! -d $deploy_directory/symlinks ]; then
  mkdir -p $deploy_directory/symlinks
fi
if [ ! -f $env_file ]; then
  cp $my_path/_laravel.env $env_file
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=$username|" $env_file
  sed -i "s|DB_USERNAME=.*|DB_USERNAME=$username|" $env_file
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$db_password|" $env_file
  sed -i "s|HORIZON_PREFIX=.*|HORIZON_PREFIX=$username|" $env_file

  echo "Created .env file: $env_file"
else
  echo "Found .env file: $env_file"
fi
EOF

  configure_typesense_env

  title "Next Steps"
  echo "1. Install the above deployment key into your Git repo."
  echo "2. Review the created .env ($env_file) and set APP_URL correctly for this application."
  echo "3. Typesense connection variables are filled automatically when the service is enabled in config.yml."
  echo "4. Re run the following: appCreate $username"

  exit
fi


# Add the SSH public key to this users authorized_keys
title "Adding SSH public key to authorized_keys for user: $username"
sudo su - $username <<EOF
if [ ! -f /home/$username/.ssh/authorized_keys ]; then
    touch /home/$username/.ssh/authorized_keys
    chmod 600 /home/$username/.ssh/authorized_keys
fi
if grep -q "$public_ssh_key" /home/$username/.ssh/authorized_keys; then
  echo "Key Already Installed: /home/$username/.ssh/authorized_keys"
else
  echo "$public_ssh_key" >> /home/$username/.ssh/authorized_keys
  echo "Key Installed: /home/$username/.ssh/authorized_keys"
fi
EOF
status "You should now be able to SSH in using this user. Something like:"
public_ip_address=$(curl -s ifconfig.me)
status "ssh -i path/to/key $username@$public_ip_address"


# Add a deployment alias for this user
title "Adding a deployment for user: $username"
alias_str="alias deploy='/usr/local/bin/devops/deploy/deploy.sh'"
sudo su - $username <<EOF
if [ ! -f /home/$username/.bash_aliases ]; then
    touch /home/$username/.bash_aliases
fi
if grep -q "$alias_str" /home/$username/.bash_aliases; then
  echo "Alias Already Exists: /home/$username/.bash_aliases"
else
  echo "$alias_str" >> /home/$username/.bash_aliases
  source /home/$username/.bashrc
  echo "Alias Created: /home/$username/.bash_aliases"
fi
EOF
status "You should now be able to deploy running 'deploy' while logged in as $username"


# Create mysql database and user
title "Updating MySQL"
status "MySQL Database: $username"
status "MySQL User: $username"
mysql -u root -p$installs_database_root_password <<SQL
CREATE DATABASE IF NOT EXISTS $username CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER IF NOT EXISTS '$username'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON $username.* TO '$username'@'localhost';
FLUSH PRIVILEGES;
SQL


title "Creating Initial Deployment"
if ! sudo -u $username $root_path/deploy/deploy.sh; then
  error "Initial deployment failed"
  exit 1
fi

title "Generating Application Key"
sudo -u $username php $deploy_directory/current/artisan key:generate

if [ "$reverb_enabled" -eq 1 ]; then
  if reverb_declared_in_composer; then
    reverb_declared=1
  fi
  if reverb_installed_for_app; then
    reverb_installed=1
  fi
fi

if [ "$reverb_enabled" -eq 1 ] && [ "$reverb_installed" -eq 1 ]; then
  title "Laravel Reverb (config + keys)"
  sudo -u "$username" bash -lc "cd $deploy_directory/current && php artisan reverb:install --no-interaction" || status "reverb:install skipped or failed (check composer package)"
  configure_reverb_env

  if [ -f "$deploy_directory/current/package.json" ] && [ -d "$deploy_directory/current/node_modules" ]; then
    title "Rebuilding Front End Assets for Reverb"
    sudo -u "$username" bash -lc "cd $deploy_directory/current && npm install && npm run build"
  fi
fi

configure_typesense_env

if [ -f $root_path/deploy/builders/$app_type/init_symlink_data.sh ]; then
  title "Creating Initial Symlinked Data"
  sudo -u $username $root_path/deploy/builders/$app_type/init_symlink_data.sh
fi

title "Creating Crontab for User: $username"
cron_expression="* * * * * cd $deploy_directory/current/ && php artisan schedule:run >> $deploy_directory/current/storage/logs/cron.log 2>&1"
if [ $(sudo -u $username crontab -l | wc -c) -eq 0 ]; then
  sudo -u $username echo "$cron_expression" | sudo crontab -u $username -
  status "Created crontab: $cron_expression"
else
  status "Found crontabs"
fi

# Create nginx conf
title "Creating Nginx Conf"
if [ ! -f /etc/nginx/sites-available/$username.conf ]; then
    sudo cp $root_path/deploy/_nginx.conf /etc/nginx/sites-available/$username.conf
    sudo sed -i "s|listen PORT;|listen $app_port;|" /etc/nginx/sites-available/$username.conf
    sudo sed -i "s|listen \[::\]:PORT;|listen [::]:$app_port;|" /etc/nginx/sites-available/$username.conf
    sudo sed -i "s|root;|root $deploy_directory/current/public;|" /etc/nginx/sites-available/$username.conf
    sudo sed -i "s|phpXXXX|php$installs_php_version-$username|" /etc/nginx/sites-available/$username.conf
    if [ "$reverb_enabled" -eq 1 ]; then
      sudo sed -i "/#REVERB_BLOCK/r $root_path/deploy/_nginx_reverb.snippet" /etc/nginx/sites-available/$username.conf
      sudo sed -i "s|REVERB_PROXY_PORT|$reverb_listen_port|g" /etc/nginx/sites-available/$username.conf
      sudo sed -i '/#REVERB_BLOCK/d' /etc/nginx/sites-available/$username.conf
    else
      sudo sed -i '/#REVERB_BLOCK/d' /etc/nginx/sites-available/$username.conf
    fi
    sudo ln -s /etc/nginx/sites-available/$username.conf /etc/nginx/sites-enabled/$username.conf
    sudo nginx -t && sudo service nginx reload
    status "Created: /etc/nginx/sites-available/$username.conf"
else
  status "Already exists: /etc/nginx/sites-available/$username.conf"
fi

title "Creating PHP-FPM Pool Conf"
if [ ! -f /etc/php/$installs_php_version/fpm/pool.d/$username.conf ]; then
    sudo cp /etc/php/$installs_php_version/fpm/pool.d/www.conf /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s|\[www\]|[$username]|" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s/user =.*/user = $username/" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s/group =.*/group = $username/" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s/listen\.owner.*/listen.owner = $username/" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s/listen\.group.*/listen.group = $username/" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo sed -i "s|listen =.*|listen = /run/php/php$installs_php_version-$username-fpm.sock|" /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    sudo service php$installs_php_version-fpm restart
    status "Created: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
else
  status "Already exists: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
fi

# Create supervisor conf (Horizon if installed, else queue:work)
title "Creating Supervisor Conf (queue worker)"
if [ -d "$deploy_directory/current/vendor/laravel/horizon" ]; then
  queue_supervisor_name="horizon_$username"
  queue_command="php $deploy_directory/current/artisan horizon"
  queue_log_name="horizon.log"
  status "Queue runner: Laravel Horizon"
else
  queue_supervisor_name="queue_$username"
  queue_command="php $deploy_directory/current/artisan queue:work --sleep=3 --tries=3 --max-time=3600"
  queue_log_name="queue-worker.log"
  status "Queue runner: artisan queue:work (Horizon not in vendor)"
fi
if [ ! -f /etc/supervisor/conf.d/$username.conf ]; then
    sudo cp $root_path/deploy/_supervisor.conf /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|program:|program:${queue_supervisor_name}|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|command=|command=${queue_command}|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|user=|user=$username|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|stdout_logfile=|stdout_logfile=$deploy_directory/current/storage/logs/${queue_log_name}|" /etc/supervisor/conf.d/$username.conf
    sudo supervisorctl reread
    sudo supervisorctl update
    status "Created: /etc/supervisor/conf.d/$username.conf ($queue_supervisor_name)"
else
  status "Already exists: /etc/supervisor/conf.d/$username.conf (edit manually if switching Horizon ↔ queue:work)"
fi
if [ -d "$deploy_directory/current/vendor/laravel/pulse" ]; then
  pulse_conf_file="/etc/supervisor/conf.d/${username}_pulse.conf"
  if [ ! -f "$pulse_conf_file" ]; then
      sudo cp $root_path/deploy/_supervisor.conf "$pulse_conf_file"
      sudo sed -i "s|program:|program:pulse_$username|" "$pulse_conf_file"
      sudo sed -i "s|command=|command=php $deploy_directory/current/artisan pulse:check|" "$pulse_conf_file"
      sudo sed -i "s|user=|user=$username|" "$pulse_conf_file"
      sudo sed -i "s|stdout_logfile=|stdout_logfile=$deploy_directory/current/storage/logs/pulse.log|" "$pulse_conf_file"
      sudo supervisorctl reread
      sudo supervisorctl update
      status "Created: $pulse_conf_file"
  else
    status "Already exists: $pulse_conf_file"
  fi
else
  status "Skipping Laravel Pulse supervisor (laravel/pulse not in vendor)"
fi

if [ "$reverb_enabled" -eq 1 ] && [ "$reverb_installed" -eq 1 ]; then
  reverb_conf_file="/etc/supervisor/conf.d/${username}_reverb.conf"
  if [ ! -f "$reverb_conf_file" ]; then
      sudo cp $root_path/deploy/_supervisor.conf "$reverb_conf_file"
      sudo supervisorctl reread
      sudo supervisorctl update
      status "Created: $reverb_conf_file"
  else
      status "Already exists: $reverb_conf_file"
  fi
  sudo sed -i "s|program:.*|program:reverb_$username|" "$reverb_conf_file"
  sudo sed -i "s|command=.*|command=php $deploy_directory/current/artisan reverb:start --host=127.0.0.1 --port=$reverb_listen_port|" "$reverb_conf_file"
  sudo sed -i "s|user=.*|user=$username|" "$reverb_conf_file"
  sudo sed -i "s|stdout_logfile=.*|stdout_logfile=$deploy_directory/current/storage/logs/reverb.log|" "$reverb_conf_file"
  sudo supervisorctl reread >/dev/null 2>&1 || true
  sudo supervisorctl update >/dev/null 2>&1 || true
  sudo supervisorctl restart "reverb_$username" >/dev/null 2>&1 || true
elif [ "$reverb_enabled" -eq 1 ] && [ "$reverb_declared" -eq 1 ]; then
  status "Reverb is declared in composer.json but not installed in vendor. Check composer install output, composer.lock constraints, and Laravel version compatibility, then deploy again."
elif [ "$reverb_enabled" -eq 1 ]; then
  status "Reverb enabled in config.yml but laravel/reverb is not declared for this app. Add the package, deploy again, then re-run create_app or add the process manually."
fi

title "Typesense (server-wide)"
status "Typesense is a system service (install via provision). Connection variables are synced into each app .env when enabled in config.yml."

# Return back to the original directory
cd $initial_working_directory || exit
