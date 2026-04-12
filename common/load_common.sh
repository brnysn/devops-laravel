#!/bin/bash

# Save current directory and cd into script path
common_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
root_path="$common_path/.."

# Load the helpers
source $common_path/helpers.sh

# Load the config file (yaml)
source $common_path/parse_yaml.sh
eval $(parse_yaml $root_path/config.yml)

servers_csv="${servers:-}"
servers=()
servers_csv="${servers_csv// /}"
case "${servers_csv,,}" in
  ""|none|off|no|false)
    ;;
  *)
    IFS="," read -r -a servers <<< "$servers_csv"
    ;;
esac


# Load the application config file
source $common_path/app_config.sh
