#!/bin/bash
echo "=== Настройка HQ-CLI ==="

hostnamectl set-hostname hq-cli.au-team.irpo; exec bash

# Сеть на клиенте будет по DHCP, поэтому настраиваем получение адреса
mkdir -p /etc/net/ifaces/ens19
echo "BOOTPROTO=dhcp" > /etc/net/ifaces/ens19/options
systemctl restart network

echo "=== HQ-CLI настроен (DHCP) ==="
