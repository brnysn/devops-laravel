#!/bin/bash

# Expecting one argument that is the app name to delete
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

# Load common (sets username, deploy_directory, … from apps/$app_name.sh)
source $my_path/../common/load_common.sh
source "$common_path/grant_supervisorctl_sudo.sh"

error "You are about to delete the following:"
status "App config name: $app_name (deployment user: $username)"
status "Application Cron: $username"
status "Directory and All Files: /home/$username/*"
status "Linux user: $username"
status "MySQL user & database: $username"
status "Nginx: /etc/nginx/sites-available/$username.conf"
status "PHP FPM Pool: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
status "Supervisor (queue/horizon): /etc/supervisor/conf.d/$username.conf"
status "Supervisor Pulse: /etc/supervisor/conf.d/${username}_pulse.conf"
status "Supervisor Reverb: /etc/supervisor/conf.d/${username}_reverb.conf"
status "App Config file: $root_path/apps/$app_name.sh"
read -p "Are you sure you continue? " response
echo    # (optional) move to a new line
if [[ $response =~ ^[Yy]$ ]]
then

  title "Nginx Configuration: /etc/nginx/sites-available/$username.conf"
  restart_nginx=0
  if [ -f /etc/nginx/sites-enabled/$username.conf ]; then
    sudo rm /etc/nginx/sites-enabled/$username.conf
    status "Deleted: /etc/nginx/sites-enabled/$username.conf"
    restart_nginx=1
  else
    status "Does not exists: /etc/nginx/sites-enabled/$username.conf"
  fi
  if [ -f /etc/nginx/sites-available/$username.conf ]; then
    sudo rm /etc/nginx/sites-available/$username.conf
    status "Deleted: /etc/nginx/sites-available/$username.conf"
    restart_nginx=1
  else
    status "Does not exists: /etc/nginx/sites-available/$username.conf"
  fi
  if [ $restart_nginx -eq 1 ]; then
    sudo service nginx reload
    status "Nginx reloaded"
  fi


  title "PHP FPM Pool: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
  if [ -f /etc/php/$installs_php_version/fpm/pool.d/$username.conf ]; then
    sudo rm /etc/php/$installs_php_version/fpm/pool.d/$username.conf
    status "Deleted: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
    sudo service php$installs_php_version-fpm restart
    status "PHP FPM reloaded"
  else
    status "Does not exists: /etc/php/$installs_php_version/fpm/pool.d/$username.conf"
  fi


  title "Supervisor Conf: /etc/supervisor/conf.d/$username.conf"
  supervisor_updated=0
  if [ -f /etc/supervisor/conf.d/$username.conf ]; then
    sudo rm /etc/supervisor/conf.d/$username.conf
    status "Deleted: /etc/supervisor/conf.d/$username.conf"
    supervisor_updated=1
  else
    status "Does not exists: /etc/supervisor/conf.d/$username.conf"
  fi
  if [ -f /etc/supervisor/conf.d/${username}_pulse.conf ]; then
    sudo rm /etc/supervisor/conf.d/${username}_pulse.conf
    status "Deleted: /etc/supervisor/conf.d/${username}_pulse.conf"
    supervisor_updated=1
  else
    status "Does not exists: /etc/supervisor/conf.d/${username}_pulse.conf"
  fi
  if [ -f /etc/supervisor/conf.d/${username}_reverb.conf ]; then
    sudo rm /etc/supervisor/conf.d/${username}_reverb.conf
    status "Deleted: /etc/supervisor/conf.d/${username}_reverb.conf"
    supervisor_updated=1
  else
    status "Does not exists: /etc/supervisor/conf.d/${username}_reverb.conf"
  fi
  if [ $supervisor_updated -eq 1 ]; then
    sudo supervisorctl reread
    sudo supervisorctl update
    status "Supervisor reloaded"
  else
    status "No supervisor configs found for $username"
  fi

  title "Removing NOPASSWD supervisorctl for $username"
  if revoke_supervisorctl_nopasswd_for_user "$username"; then
    status "Removed /etc/sudoers.d/10-deploy-supervisorctl-${username} if present"
  else
    status "Warning: could not remove supervisorctl sudoers drop-in for $username"
  fi

  title "Deleting Application Cron"
  if ! id "$username" >/dev/null 2>&1; then
    status "User $username does not exist; skipping crontab removal"
  elif [ $(sudo -u "$username" crontab -l 2>/dev/null | wc -c) -eq 0 ]; then
    status "Crontab does not exist"
  else
    sudo -u "$username" crontab -r
    status "Crontab deleted"
  fi


  title "Removing www-data from $username group"
  if getent group "$username" | grep -qw "www-data"; then
    sudo deluser www-data "$username"
    status "Removed www-data from $username group"
  else
    status "www-data not part of the group"
  fi

  title "Dropping MySQL user & database for $username"
  mysql -u root -p$installs_database_root_password <<SQL
DROP DATABASE IF EXISTS \`$username\`;
DROP USER IF EXISTS '$username'@'localhost';
FLUSH PRIVILEGES;
SQL
  status "Dropped MySQL user and database: $username"

  title "Deleting Linux user and home: $username"
  if id "$username" >/dev/null 2>&1; then
    sudo deluser "$username" --remove-all-files
    status "User $username has been deleted."
  else
    status "User $username does not exist."
  fi
  if [[ -d /home/$username ]]; then
    sudo rm -rf /home/$username
    status "Deleted: /home/$username"
  else
    status "Does not exists: /home/$username"
  fi

  title "Deleting Application Config: $root_path/apps/$app_name.sh"
  if [ -f $root_path/apps/$app_name.sh ]; then
    sudo rm $root_path/apps/$app_name.sh
    status "Deleted: $root_path/apps/$app_name.sh"
  else
    status "Does not exists: $root_path/apps/$app_name.sh"
  fi
fi

# Return back to the original directory
cd $initial_working_directory || exit
