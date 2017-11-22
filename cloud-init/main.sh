#!/bin/bash
set -x
cat << 'EOF' > /root/inventory
[local]
localhost ansible_connection=local
EOF

sudo apt-get update
sudo apt-get install software-properties-common -y
sudo apt-add-repository ppa:ansible/ansible -y
sudo apt-get update
sudo apt-get install ansible -y

cat << 'EOF' > /etc/ansible/ansible.cfg
[defaults]
remote_tmp=$HOME/.ansible/tmp
local_tmp=$HOME/.ansible/tmp
pipelining = True
retry_files_enabled = False
host_key_checking = False
timeout = 60
EOF

${ansible_command}