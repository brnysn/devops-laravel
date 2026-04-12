#!/bin/bash

builder_directory=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Build the application
title "Laravel Builder"

# Add symlinks before building
status "Create Symlinks"
source $builder_directory/symlinks.sh

if [ ! -f archived_deployed.lock ]; then
  status "Composer Install"
  if ! composer install; then
    error "Composer install failed"
    return 1 2>/dev/null || exit 1
  fi

  status "NPM Install"
  if ! npm install; then
    error "NPM install failed"
    return 1 2>/dev/null || exit 1
  fi

  status "Build Front End Assets"
  if ! npm run build; then
    error "Front end build failed"
    return 1 2>/dev/null || exit 1
  fi
else
  status "Build completed when creating archive"
fi

status "Migrations"
if ! php artisan migrate --force; then
  error "Database migrations failed"
  return 1 2>/dev/null || exit 1
fi
