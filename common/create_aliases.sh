#!/bin/bash

if [ ! -f ~/.bash_aliases ]; then
    touch ~/.bash_aliases
fi

declare -a aliases=(
"alias appList='/usr/local/bin/devops/deploy/list_apps.sh'"
"alias appNew='/usr/local/bin/devops/deploy/new_app_form.sh'"
"alias appCreate='/usr/local/bin/devops/deploy/create_app.sh'"
"alias appDelete='/usr/local/bin/devops/deploy/delete_app.sh'"
"alias art='php artisan'"
"alias dumpa='composer dumpa && art optimize:clear'"
"alias migrate='art migrate'"
"alias mf='art migrate:fresh'"
"alias mfs='art migrate:fresh --seed'"
"alias tinker='art optimize:clear && art tinker'"
                )
need_to_resource=0
for alias_str in "${aliases[@]}"
do
   if grep -q "$alias_str" ~/.bash_aliases; then
    echo "Alias Already Exists: $alias_str"
  else
    echo "$alias_str" >> ~/.bash_aliases
    echo "Alias Created: $alias_str"
    need_to_resource=1
  fi
done

if [ $need_to_resource -eq 1 ]; then
  echo "To use the new aliases in this shell, run: source ~/.bash_aliases"
fi

# Loading into the current shell when this file is sourced (e.g. source common/create_aliases.sh)
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" != "${0}" ] && [ -f ~/.bash_aliases ]; then
  # shellcheck source=/dev/null
  source ~/.bash_aliases
fi
