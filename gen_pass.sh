#!/bin/bash

generate_strong_password() {
    local length=$1
    < /dev/urandom LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?/~' | head -c"$length"
}

generate_simple_password() {
    local length=$1
    < /dev/urandom LC_ALL=C tr -dc 'A-Za-z0-9._-' | head -c"$length"
}

# Функция для экранирования слэшей
escape_slashes() {
    echo "$1" | sed 's|/|\\/|g' | sed 's|&|\\&|g'
}

FILE="./inventory/group_vars/netbox/secrets.yml"

[ -a $FILE ] || cp "./inventory/group_vars/netbox/example_secrets.yml" "./inventory/group_vars/netbox/secrets.yml"

VRRP_PASS=$(escape_slashes "$(generate_strong_password 8)")
PG_SUPER_PASS=$(escape_slashes "$(generate_strong_password 16)")
REPL_PASS=$(escape_slashes "$(generate_strong_password 15)")
REDIS_PASS=$(escape_slashes "$(generate_simple_password 32)")
PGB_ADMIN_PASS=$(escape_slashes "$(generate_strong_password 10)")
PGB_STATS_PASS=$(escape_slashes "$(generate_strong_password 13)")
NETBOX_PEPPERS=$(openssl rand -hex 32)
NETBOX_SECRET=$(escape_slashes "$(generate_strong_password 50)")

sed -i '' "/vrrp_auth_pass: /s/\".*\"/\"$VRRP_PASS\"/" "$FILE"
sed -i '' "/pg_superuser_password: /s/\".*\"/\"$PG_SUPER_PASS\"/" "$FILE"
sed -i '' "/replication_password: /s/\".*\"/\"$REPL_PASS\"/" "$FILE"
sed -i '' "/redis_password: /s/\".*\"/\"$REDIS_PASS\"/" "$FILE"
sed -i '' "/pgb_admin_pass: /s/\".*\"/\"$PGB_ADMIN_PASS\"/" "$FILE"
sed -i '' "/pgb_stats_pass: /s/\".*\"/\"$PGB_STATS_PASS\"/" "$FILE"
sed -i '' "/netbox_peppers: /s/\".*\"/\"$NETBOX_PEPPERS\"/" "$FILE"
sed -i '' "/netbox_secret_key: /s/\".*\"/\"$NETBOX_SECRET\"/" "$FILE"
