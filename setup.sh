#!/usr/bin/env bash
# This script setups dockerized Redash on Ubuntu 20.04.
set -eu

REDASH_BASE_PATH=/opt/redash

install_docker() {
  # Install Docker
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get -qqy update
  DEBIAN_FRONTEND=noninteractive sudo -E apt-get -qqy -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
  sudo apt-get -yy install apt-transport-https ca-certificates curl software-properties-common pwgen gnupg sed gawk
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=""$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ""$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Install Docker Compose
  sudo ln -sfv /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

  # Allow current user to run Docker commands
  sudo usermod -aG docker "$USER"
}

create_directories() {
  if [ ! -e "$REDASH_BASE_PATH" ]; then
    sudo mkdir -p "$REDASH_BASE_PATH"
    sudo chown "$USER:" "$REDASH_BASE_PATH"
  fi

  if [ ! -e "$REDASH_BASE_PATH"/postgres-data ]; then
    mkdir "$REDASH_BASE_PATH"/postgres-data
  fi

  if [ ! -e "$REDASH_BASE_PATH"/simpleSAMLphp ]; then
    mkdir "$REDASH_BASE_PATH"/simpleSAMLphp
  fi

  if [ ! -e "$REDASH_BASE_PATH"/simpleSAMLphp/config ]; then
    mkdir "$REDASH_BASE_PATH"/simpleSAMLphp/config
  fi

  if [ ! -e "$REDASH_BASE_PATH"/simpleSAMLphp/config/apache ]; then
    mkdir "$REDASH_BASE_PATH"/simpleSAMLphp/config/apache
  fi

  if [ ! -e "$REDASH_BASE_PATH"/simpleSAMLphp/config/simplesamlphp ]; then
    mkdir "$REDASH_BASE_PATH"/simpleSAMLphp/config/simplesamlphp
  fi
}

create_config() {
  if [ -e "$REDASH_BASE_PATH"/env ]; then
    rm "$REDASH_BASE_PATH"/env
    touch "$REDASH_BASE_PATH"/env
  fi

  COOKIE_SECRET=$(pwgen -1s 32)
  SECRET_KEY=$(pwgen -1s 32)
  POSTGRES_PASSWORD=$(pwgen -1s 32)
  REDASH_DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres"

  cat <<EOF >"$REDASH_BASE_PATH"/env
PYTHONUNBUFFERED=0
REDASH_LOG_LEVEL=INFO
REDASH_REDIS_URL=redis://redis:6379/0
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDASH_COOKIE_SECRET=$COOKIE_SECRET
REDASH_SECRET_KEY=$SECRET_KEY
REDASH_DATABASE_URL=$REDASH_DATABASE_URL
EOF
}

setup_compose() {
  REQUESTED_CHANNEL=stable
  LATEST_VERSION=$(curl -s "https://version.redash.io/api/releases?channel=$REQUESTED_CHANNEL" | json_pp | grep "docker_image" | head -n 1 | awk 'BEGIN{FS=":"}{print $3}' | awk 'BEGIN{FS="\""}{print $1}')

  cd "$REDASH_BASE_PATH"
  GIT_BRANCH="${REDASH_BRANCH:-master}" # Default branch/version to master if not specified in REDASH_BRANCH env var
  # curl -OL https://raw.githubusercontent.com/getredash/setup/"$GIT_BRANCH"/data/docker-compose.yml
  # sed -ri "s/image: redash\/redash:([A-Za-z0-9.-]*)/image: redash\/redash:$LATEST_VERSION/" docker-compose.yml
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/docker-compose.yml
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/Dockerfile
  if [ $# -lt 1 ]; then
    IP=$(hostname -I | awk '{print $1}')
  else
    IP=$1
  fi
  echo "USING $IP TO ACESS REDASH, MAKE SURE CLIENT CAN CONNECT TO THIS TOO"
  sed -i "s/localhost/$IP/g" "$REDASH_BASE_PATH/docker-compose.yml"
  cd "$REDASH_BASE_PATH/simpleSAMLphp"
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/Dockerfile
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/authsources.php
  cd "$REDASH_BASE_PATH/simpleSAMLphp/config/apache"
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/apache/ports.conf.mo
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/apache/simplesamlphp.conf.mo
  cd "$REDASH_BASE_PATH/simpleSAMLphp/config/simplesamlphp"
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/simplesamlphp/authsources.php
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/simplesamlphp/config.php
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/simplesamlphp/saml20-sp-remote.php
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/simplesamlphp/server.crt
  curl -OL https://raw.githubusercontent.com/M3m3M4n/RedashSetup/master/data/simpleSAMLphp/config/simplesamlphp/server.pem
  cd "$REDASH_BASE_PATH"
  echo "export COMPOSE_PROJECT_NAME=redash" >>~/.profile
  echo "export COMPOSE_FILE=$REDASH_BASE_PATH/docker-compose.yml" >>~/.profile
  export COMPOSE_PROJECT_NAME=redash
  export COMPOSE_FILE="$REDASH_BASE_PATH"/docker-compose.yml
  sudo docker-compose run --rm server create_db
  sudo docker-compose up -d
}

install_docker
create_directories
create_config
setup_compose $1
