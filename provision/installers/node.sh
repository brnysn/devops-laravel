#!/bin/bash

# NodeJS — LTS 22.x (Node 21 + "npm install -g npm" pulls npm 11, which does not support Node 21)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

## Update Package Lists
sudo apt-get update -y

# Install Node (NodeSource ships a compatible npm; avoid upgrading npm past engine support)
sudo apt install -y nodejs
sudo /usr/bin/npm install -g gulp-cli
sudo /usr/bin/npm install -g bower
sudo /usr/bin/npm install -g yarn
sudo /usr/bin/npm install -g grunt-cli