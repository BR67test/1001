#!/bin/bash
echo "=== BR-SRV (Модуль 3 - Ansible инвентаризация) ==="

mkdir -p /etc/ansible/PC-INFO

apt-get update && apt-get install -y ansible

cat > /etc/ansible/inventory_hq.yml <<'EOF'
---
- name: Инвентаризация машин HQ-SRV и HQ-CLI
  hosts: hq_workstations
  gather_facts: yes
  tasks:
    - name: Сбор информации о хосте
      copy:
        content: |
          hostname: {{ ansible_hostname }}
          ip_address: {{ ansible_default_ipv4.address | default('N/A') }}
        dest: "/etc/ansible/PC-INFO/{{ ansible_hostname }}.yml"
      delegate_to: localhost
EOF

cat > /etc/ansible/hosts <<'EOF'
[hq_workstations]
HQ-SRV ansible_host=192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd1! ansible_port=2026
HQ-CLI ansible_host=192.168.200.4 ansible_user=sshuser ansible_password=P@ssw0rd1! ansible_port=2026
EOF

ansible-playbook -i /etc/ansible/hosts /etc/ansible/inventory_hq.yml

echo "=== Отчёты в /etc/ansible/PC-INFO/ ==="
ls -la /etc/ansible/PC-INFO/
cat /etc/ansible/PC-INFO/*.yml

echo "=== BR-SRV (Модуль 3 - Ansible) готов ==="
