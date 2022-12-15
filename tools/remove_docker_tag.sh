#!/usr/bin/env bash

set -euo pipefail

USERNAME="${1}"
PASSWORD="${2}"
ORGANIZATION="${3}"
IMAGE="${4}"
TAG="${5}"

function login_data() {
cat <<EOF
{
  "username": "$USERNAME",
  "password": "$PASSWORD"
}
EOF
}

TOKEN=`curl -s -H "Content-Type: application/json" -X POST -d "$(login_data)" "https://hub.docker.com/v2/users/login/" | jq -r .token`

curl "https://hub.docker.com/v2/repositories/${ORGANIZATION}/${IMAGE}/tags/${TAG}/" \
-X DELETE \
-H "Authorization: JWT ${TOKEN}"
