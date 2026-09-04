#!/bin/bash

set -e

PROJECT_DIR="$HOME/netology-diplom"
SSH_CONFIG="$HOME/.ssh/config"

cd "$PROJECT_DIR"

BASTION_IP=$(terraform output -raw bastion_public_ip)

if [ -z "$BASTION_IP" ]; then
    echo "Ошибка: Terraform не вернул IP Bastion"
    exit 1
fi

echo "Новый IP Bastion: $BASTION_IP"

mkdir -p "$HOME/.ssh"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Удаляем предыдущий автоматически созданный блок
sed -i '/^# BEGIN NETOLOGY DIPLOM$/,/^# END NETOLOGY DIPLOM$/d' "$SSH_CONFIG"

cat >> "$SSH_CONFIG" <<EOF

# BEGIN NETOLOGY DIPLOM
Host bastion
    HostName $BASTION_IP
    User ubuntu
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host web01.ru-central1.internal
    User ubuntu
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host web02.ru-central1.internal
    User ubuntu
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host zabbix.ru-central1.internal
    User ubuntu
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
# END NETOLOGY DIPLOM
EOF

echo "SSH config обновлён."
