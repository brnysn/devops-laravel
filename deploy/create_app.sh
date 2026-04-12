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

# Reverb (config.yml installs.reverb.install): port stable per username; nginx + .env + daemon when enabled
reverb_enabled=0
case "${installs_reverb_install:-}" in
  [yY][eE][sS]|[yY]) reverb_enabled=1 ;;
esac
reverb_listen_port=$(( 9080 + $(printf '%s' "$username" | cksum | awk '{print $1 % 1000}') ))

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
if [ ! -f $deploy_directory/symlinks/.env ]; then
  cp $my_path/_laravel.env $deploy_directory/symlinks/.env
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=$username|" $deploy_directory/symlinks/.env
  sed -i "s|DB_USERNAME=.*|DB_USERNAME=$username|" $deploy_directory/symlinks/.env
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$db_password|" $deploy_directory/symlinks/.env
  sed -i "s|HORIZON_PREFIX=.*|HORIZON_PREFIX=$username|" $deploy_directory/symlinks/.env
  if [ "$reverb_enabled" -eq 1 ]; then
    grep -q '^REVERB_HOST=' $deploy_directory/symlinks/.env || echo "REVERB_HOST=127.0.0.1" >> $deploy_directory/symlinks/.env
    grep -q '^REVERB_PORT=' $deploy_directory/symlinks/.env || echo "REVERB_PORT=$reverb_listen_port" >> $deploy_directory/symlinks/.env
    grep -q '^REVERB_SCHEME=' $deploy_directory/symlinks/.env || echo "REVERB_SCHEME=http" >> $deploy_directory/symlinks/.env
  fi

  echo "Created .env file: $deploy_directory/symlinks/.env"
else
  echo "Found .env file: $deploy_directory/symlinks/.env"
fi
EOF

  title "Next Steps"
  echo "1. Install the above deployment key into your Git repo."
  echo "2. Review the created .env ($deploy_directory/symlinks/.env) and make desired changes."
  echo "3. For Typesense: set .env if using Scout (server service from provision)."
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
sudo -u $username $root_path/deploy/deploy.sh

title "Generating Application Key"
sudo -u $username php $deploy_directory/current/artisan key:generate

if [ "$reverb_enabled" -eq 1 ] && [ -d "$deploy_directory/current/vendor/laravel/reverb" ]; then
  title "Laravel Reverb (config + keys)"
  sudo -u "$username" sed -i "s/^REVERB_HOST=.*/REVERB_HOST=127.0.0.1/" "$deploy_directory/symlinks/.env" 2>/dev/null || true
  sudo -u "$username" sed -i "s/^REVERB_PORT=.*/REVERB_PORT=$reverb_listen_port/" "$deploy_directory/symlinks/.env" 2>/dev/null || true
  grep -q '^REVERB_HOST=' "$deploy_directory/symlinks/.env" || echo "REVERB_HOST=127.0.0.1" | sudo -u "$username" tee -a "$deploy_directory/symlinks/.env" >/dev/null
  grep -q '^REVERB_PORT=' "$deploy_directory/symlinks/.env" || echo "REVERB_PORT=$reverb_listen_port" | sudo -u "$username" tee -a "$deploy_directory/symlinks/.env" >/dev/null
  sudo -u "$username" bash -lc "cd $deploy_directory/current && php artisan reverb:install --no-interaction" || status "reverb:install skipped or failed (check composer package)"
  sudo -u "$username" sed -i "s/^REVERB_HOST=.*/REVERB_HOST=127.0.0.1/" "$deploy_directory/symlinks/.env" 2>/dev/null || true
  sudo -u "$username" sed -i "s/^REVERB_PORT=.*/REVERB_PORT=$reverb_listen_port/" "$deploy_directory/symlinks/.env" 2>/dev/null || true
fi

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
    status "Created: /etc/php/$installs_php_version/fpm/pool.d/$username"
else
  status "Already existsL /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
fi

# Create supervisor conf
title "Creating Supervisor Conf"
if [ ! -f /etc/supervisor/conf.d/$username.conf ]; then
    sudo cp $root_path/deploy/_supervisor.conf /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|program:|program:horizon_$username|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|command=|command=php $deploy_directory/current/artisan horizon|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|user=|user=$username|" /etc/supervisor/conf.d/$username.conf
    sudo sed -i "s|stdout_logfile=|stdout_logfile=$deploy_directory/current/storage/logs/horizon.log|" /etc/supervisor/conf.d/$username.conf
    sudo supervisorctl reread
    sudo supervisorctl update
    status "Created: /etc/supervisor/conf.d/$username.conf"
else
  status "Already exists: /etc/supervisor/conf.d/$username.conf"
fi
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

if [ "$reverb_enabled" -eq 1 ] && [ -d "$deploy_directory/current/vendor/laravel/reverb" ]; then
  reverb_conf_file="/etc/supervisor/conf.d/${username}_reverb.conf"
  if [ ! -f "$reverb_conf_file" ]; then
      sudo cp $root_path/deploy/_supervisor.conf "$reverb_conf_file"
      sudo sed -i "s|program:|program:reverb_$username|" "$reverb_conf_file"
      sudo sed -i "s|command=|command=php $deploy_directory/current/artisan reverb:start|" "$reverb_conf_file"
      sudo sed -i "s|user=|user=$username|" "$reverb_conf_file"
      sudo sed -i "s|stdout_logfile=|stdout_logfile=$deploy_directory/current/storage/logs/reverb.log|" "$reverb_conf_file"
      sudo supervisorctl reread
      sudo supervisorctl update
      status "Created: $reverb_conf_file"
  else
      status "Already exists: $reverb_conf_file"
  fi
elif [ "$reverb_enabled" -eq 1 ]; then
  status "Reverb enabled in config.yml but laravel/reverb not in composer — add the package to the repo, deploy again, then re-run create_app or add the process manually."
fi

title "Typesense (server-wide)"
status "Typesense is a system service (install via provision). Configure host/API key in .env for Scout or your client; no per-app supervisor entry."

# Return back to the original directory
cd $initial_working_directory || exit
