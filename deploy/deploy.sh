#!/bin/bash

# Application to deploy is same as current username
app_name=$(whoami)

# Save current directory and cd into script path
initial_working_directory=$(pwd)
my_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd $my_path

# Load common
source $my_path/../common/load_common.sh

keep_releases="${deploy_keep_releases:-6}"
case "$keep_releases" in
  ''|*[!0-9]*)
    keep_releases=6
    ;;
esac
if [ "$keep_releases" -lt 1 ]; then
  keep_releases=1
fi

cleanup_old_deployments() {
  local keep_count="$1"
  local reason="$2"
  local release_dirs=()
  local release_dir
  local current_release
  local removed_count=0

  current_release=$(readlink -f "$deploy_directory/current" 2>/dev/null || true)

  while IFS= read -r release_dir; do
    [ -n "$release_dir" ] || continue
    release_dirs+=("$release_dir")
  done < <(find "$deploy_directory/releases" -mindepth 1 -maxdepth 1 -type d | sort -r)

  title "$reason"
  status "Keeping the most recent $keep_count release(s)"

  if [ ${#release_dirs[@]} -le "$keep_count" ]; then
    status "Found ${#release_dirs[@]} release(s); nothing to delete"
    return 0
  fi

  for release_dir in "${release_dirs[@]:keep_count}"; do
    if [ -n "$current_release" ] && [ "$release_dir" = "$current_release" ]; then
      status "Keeping active release: $release_dir"
      continue
    fi
    rm -rf -- "$release_dir"
    status "Deleted: $release_dir"
    removed_count=$((removed_count + 1))
  done

  status "Deleted $removed_count old release(s)"
}

title "Deploying to other servers"
# NOTE: This is a bit sketchy
# We only have the ubuntu user on this node that can connect to the other nodes
# So we need to use the scp/ssh commands with ubuntu user sessions....not ideal
# This also assumes that the deployment user is the same on all nodes
#
status "servers: ${servers_csv:-none}"
if [ ${#servers[@]} -gt 0 ]; then
  for i in "${!servers[@]}"; do
    if [ -f $deploy_directory/build*.zip ]; then
      # copy the build to the other server
      scp -i ~/.ssh/laravel_demo.pem $deploy_directory/build*.zip  ubuntu@${servers[$i]}:/home/ubuntu
      # move the zip file to the deployment user (assumes same username)
      # chown to set the owner of the zip to the deployment user
      # run the deployment script on the other node
      ssh -i ~/.ssh/laravel_demo.pem ubuntu@"${servers[$i]}" <<ENDSSH
        sudo mv /home/ubuntu/build*.zip /home/$username/deployments
        sudo chown -R $username:$username /home/$username/deployments
        sudo -u $username /usr/local/bin/devops/deploy/deploy.sh
ENDSSH
      status "Build copied and deployed to: ${servers[$i]}"
    fi
  done
else
  status "No other servers configured"
fi

# Assuming this file is being run as the deployment user
current_user=$(whoami)
if [ ! "$username" == "$current_user" ]; then
  error "Expected user: $username"
  error "Current user: $current_user"
  error "Try running like sudo -u app_name deploy.sh"
  exit 1
fi


title "Starting Deployment: $username"

# Initialize the deployment directory structure
if [ ! -d $deploy_directory/releases ]; then
    mkdir -p $deploy_directory/releases
fi

cleanup_old_deployments "$keep_releases" "Pre-Deploy Cleanup"

# Deployments will be prefixed with the current timestamp
date_string=$(date +"%Y-%m-%d-%H-%M-%S")

# Deployments are post fixed with the shortened git hash
if [ -d $deploy_directory/current ]; then
  cd $deploy_directory/current/
  remote_git_line=$(git ls-remote | head -n 1)
  remote_hash=${remote_git_line:0:7}
  local_hash=$(git rev-parse --short HEAD 2> /dev/null | sed "s/\(.*\)/\1/")
  status "remote_hash=$remote_hash, local_hash=$local_hash"
  if [ $remote_hash = $local_hash ]; then
    status "No code changes detected...but deploying anyway!"
  fi
fi

# Create the directory name
foldername="$date_string-$remote_hash"
version_str=$foldername
status "Folder Name: $foldername"
status "Deployment Directory: $deploy_directory/releases/$foldername"

cd $deploy_directory/releases
if [ -f $deploy_directory/build*.zip ]; then
  # Deploy from an archive
  status "Deploying from an archive..."

  # Create version string based on archive name
  file=$(ls "$deploy_directory" | grep "^build.*zip$" | head -1)
  version_str=$(echo "$file" | cut -f 1 -d '.')
  echo "file=$file"
  echo "version_str=$version_str"

  # Unzip the archive
  mkdir $foldername
  cd $foldername
  unzip -q $deploy_directory/build*.zip
  touch "archived_deployed.lock"

  # Delete the original
  rm $deploy_directory/build*.zip
else
  # Git clone into this new directory
  status "Deploying from a git repository..."
  git clone --depth 1 $repo $foldername
fi

cd $deploy_directory/releases/$foldername

# Allow the group (www-data) to write to the hash files
chmod 660 hash*

# Build the application
source $my_path/builders/$app_type/build.sh

# publish git hash into .env
title "Updating APP_VERSION in the .env"
if [ -f $deploy_directory/symlinks/.env ]; then
  echo "app_version=$version_str"
  sed -i "s|APP_VERSION=.*|APP_VERSION=$version_str|" $deploy_directory/symlinks/.env
fi

# Activate this version
title "Activate"
if [[ -h $deploy_directory/current ]]; then
  current_link=$(readlink $deploy_directory/current)
  status "Unlinking: $current_link"
  unlink $deploy_directory/current
fi
status "  Linking: $deploy_directory/releases/$foldername"
ln -sf $deploy_directory/releases/$foldername $deploy_directory/current

laravel_root="$deploy_directory/current"
if [ ! -f "$laravel_root/composer.json" ]; then
  found=""
  while IFS= read -r -d '' candidate; do
    if grep -q 'laravel/framework' "$candidate" 2>/dev/null; then
      found="$candidate"
      break
    fi
  done < <(find "$deploy_directory/current" -maxdepth 5 -name composer.json -type f -print0 2>/dev/null)
  if [ -n "$found" ]; then
    laravel_root=$(dirname "$found")
    status "Laravel root (nested): $laravel_root"
  else
    status "Warning: composer.json not found under $deploy_directory/current; using default root for artisan signals"
  fi
fi

title "Refreshing Long-Running Processes"
# Graceful Laravel signals (workers finish current job / Horizon master exits / Reverb sees cache flag).
if [ -d "$laravel_root/vendor/laravel/horizon" ]; then
  php "$laravel_root/artisan" horizon:terminate >/dev/null 2>&1 || status "Could not signal Horizon restart"
  status "Signaled Horizon to restart on the new release"
else
  php "$laravel_root/artisan" queue:restart >/dev/null 2>&1 || status "Could not signal queue workers to restart"
  status "Signaled queue workers to restart on the new release"
fi
if [ -d "$laravel_root/vendor/laravel/reverb" ]; then
  php "$laravel_root/artisan" reverb:restart >/dev/null 2>&1 || status "Could not signal Reverb restart (cache may be unreachable; Supervisor restart below)"
  status "Signaled Reverb to restart on the new release (uses app cache like queue:restart)"
fi

# Supervisor hard restart: guarantees new code is loaded even if graceful signals missed (e.g. reverb:restart
# and running reverb:start not sharing the same cache store). Uses sudo -n when available so deploy user
# does not need an interactive password.
title "Supervisor: restart queue/horizon and Reverb"
supervisorctl_try() {
  command -v supervisorctl >/dev/null 2>&1 || return 1
  if sudo -n supervisorctl "$@" 2>/dev/null; then
    return 0
  fi
  supervisorctl "$@"
}

queue_supervisor_program=""
if [ -f "/etc/supervisor/conf.d/${username}.conf" ]; then
  if [ -d "$laravel_root/vendor/laravel/horizon" ]; then
    queue_supervisor_program="horizon_${username}"
  else
    queue_supervisor_program="queue_${username}"
  fi
fi

if [ -n "$queue_supervisor_program" ]; then
  if supervisorctl_try restart "$queue_supervisor_program"; then
    status "Supervisor restarted: $queue_supervisor_program"
  else
    status "Could not supervisorctl restart $queue_supervisor_program (run as root or configure sudo -n for supervisorctl)"
  fi
else
  status "No /etc/supervisor/conf.d/${username}.conf — skipping queue/horizon Supervisor restart"
fi

if [ -d "$laravel_root/vendor/laravel/reverb" ] && [ -f "/etc/supervisor/conf.d/${username}_reverb.conf" ]; then
  if supervisorctl_try restart "reverb_${username}"; then
    status "Supervisor restarted: reverb_${username}"
  else
    status "Could not supervisorctl restart reverb_${username}"
  fi
elif [ -d "$laravel_root/vendor/laravel/reverb" ]; then
  status "Reverb in vendor but no /etc/supervisor/conf.d/${username}_reverb.conf — run create_app or add the program"
fi

if command -v supervisorctl >/dev/null 2>&1; then
  sleep 1
  if [ -n "$queue_supervisor_program" ]; then
    if supervisorctl_try status "$queue_supervisor_program" 2>/dev/null | grep -q RUNNING; then
      status "Supervisor reports $queue_supervisor_program: RUNNING"
    else
      status "Warning: $queue_supervisor_program not RUNNING after restart — check: sudo supervisorctl status"
    fi
  fi
  if [ -d "$laravel_root/vendor/laravel/reverb" ] && [ -f "/etc/supervisor/conf.d/${username}_reverb.conf" ]; then
    if supervisorctl_try status "reverb_${username}:*" 2>/dev/null | grep -q RUNNING; then
      status "Supervisor reports reverb_${username}: RUNNING"
    else
      status "Warning: reverb_${username} not RUNNING after restart — check logs under storage/logs/reverb.log"
    fi
  fi
fi

# Cleanup Old Deployments
cleanup_old_deployments "$keep_releases" "Post-Deploy Cleanup"


# Return back to the original directory
cd $initial_working_directory
