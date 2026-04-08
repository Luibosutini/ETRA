#!/bin/sh
# 起動時に app-config.js の環境変数プレースホルダーを置換する

set -e

CONFIG_TPL="/usr/share/nginx/html/app-config.js.tpl"
CONFIG_OUT="/usr/share/nginx/html/app-config.js"

if [ -f "$CONFIG_TPL" ]; then
    envsubst \
        '${DATASTORE_ID} ${REGION} ${COGNITO_USER_POOL_ID} ${COGNITO_CLIENT_ID} ${APP_URL}' \
        < "$CONFIG_TPL" > "$CONFIG_OUT"
    echo "app-config.js generated from template"
fi
