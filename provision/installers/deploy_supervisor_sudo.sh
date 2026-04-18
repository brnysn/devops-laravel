#!/bin/bash
# Run from provision (as root). Grant supervisorctl NOPASSWD for every user under /home/* that
# has a deployments directory (Laravel deploy users). create_app also grants for new users.

_installer_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=../../common/grant_supervisorctl_sudo.sh
source "$_installer_dir/../../common/grant_supervisorctl_sudo.sh"

if ! command -v supervisorctl >/dev/null 2>&1; then
  status "supervisorctl not found; skipping sudoers drop-ins"
  return 0
fi

granted_any=0
shopt -s nullglob
for home in /home/*/; do
  [ -d "$home" ] || continue
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  [ -d "$home/deployments" ] || continue
  if grant_supervisorctl_nopasswd_for_user "$u"; then
    status "NOPASSWD supervisorctl for deploy user: $u"
    granted_any=1
  else
    status "Warning: could not write sudoers for $u"
  fi
done
shopt -u nullglob

if [ "$granted_any" -eq 0 ]; then
  status "No /home/*/deployments users found; create_app will add sudoers when each app user is created"
fi
