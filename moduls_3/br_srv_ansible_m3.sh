#!/bin/bash
echo "=== BR-SRV (Модуль 3 - Ansible инвентаризация) ==="

mkdir -p /etc/ansible/PC_INFO

apt-get update && apt-get install -y ansible dos2unix

cat > /etc/ansible/inventory.yml <<'EOF'
---
- name: Инвентаризация машин HQ-SRV и HQ-CLI
  hosts: hq-srv,hq-cli
  gather_facts: yes
  vars:
    ansible_python_interpreter: /usr/bin/python3
  tasks:
    - name: Сбор информации о хосте
      set_fact:
        host_info:
          name: "{{ ansible_hostname }}"
          ip: "{{ ansible_default_ipv4.address | default('N/A') }}"

    - name: Сохранение информации в файл
      copy:
        content: |
          ---
          hostname: {{ host_info.name }}
          ip_address: {{ host_info.ip }}
          timestamp: "{{ ansible_date_time.iso8601 }}"
        dest: "/etc/ansible/PC_INFO/{{ host_info.name }}.yml"
      delegate_to: localhost
      run_once: true
EOF

cat > /etc/ansible/hosts <<'EOF'
[hq-srv]
192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd! ansible_port=2026

[hq-cli]
192.168.200.4 ansible_user=sshuser ansible_password=P@ssw0rd! ansible_port=2026
EOF

cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
host_key_checking = False
inventory = /etc/ansible/hosts
interpreter_python = /usr/bin/python3
EOF

ansible-playbook /etc/ansible/inventory.yml

echo "=== Отчёты в /etc/ansible/PC_INFO/ ==="
ls -la /etc/ansible/PC_INFO/
cat /etc/ansible/PC_INFO/*.yml

echo "=== BR-SRV (Модуль 3 - Ansible) готов ==="
