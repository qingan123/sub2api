#!/usr/bin/env bash
set -Eeuo pipefail
export REPO_URL=${REPO_URL:-https://github.com/Wei-Shaw/sub2api.git}
export APP_DIR=${APP_DIR:-/opt/sub2api-official}
exec bash "$(dirname "$0")/install.sh"
