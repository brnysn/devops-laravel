#!/bin/bash
# Grant a Linux user passwordless sudo for supervisorctl only (exact path), so deploy.sh can
# restart queue/horizon/reverb without an interactive root shell.
# When already root (provision), uses tee/chmod/visudo directly; otherwise uses sudo.

grant_supervisorctl_nopasswd_for_user() {
  local target_user="$1" sc f line prefix=()
  [ -n "$target_user" ] || return 1
  id "$target_user" >/dev/null 2>&1 || return 1
  sc=$(command -v supervisorctl 2>/dev/null) || return 1
  sc=$(readlink -f "$sc" 2>/dev/null || printf '%s' "$sc")
  f="/etc/sudoers.d/10-deploy-supervisorctl-${target_user}"
  line="${target_user} ALL=(ALL) NOPASSWD:${sc}"
  if [ "$(id -u)" -ne 0 ]; then
    prefix=(sudo)
  fi
  printf '%s\n' "$line" | "${prefix[@]}" tee "$f" >/dev/null || return 1
  "${prefix[@]}" chmod 440 "$f" || return 1
  if ! "${prefix[@]}" visudo -c -f "$f" >/dev/null 2>&1; then
    "${prefix[@]}" rm -f "$f"
    return 1
  fi
  return 0
}

revoke_supervisorctl_nopasswd_for_user() {
  local target_user="$1" f prefix=()
  [ -n "$target_user" ] || return 1
  f="/etc/sudoers.d/10-deploy-supervisorctl-${target_user}"
  if [ "$(id -u)" -ne 0 ]; then
    prefix=(sudo)
  fi
  if [ -f "$f" ]; then
    "${prefix[@]}" rm -f "$f"
  fi
  return 0
}
