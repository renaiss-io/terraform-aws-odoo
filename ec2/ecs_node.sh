#!/bin/bash

# Install requisites
sudo yum install -y unzip

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install odoo conf file
mkdir -p /etc/odoo
aws secretsmanager get-secret-value --secret-id ${ conf_secret } --query "SecretString" --output text > /etc/odoo/odoo.conf

# Register instance to ECS cluster
cat <<'EOF' >> /etc/ecs/ecs.config
ECS_CLUSTER=${name}
ECS_LOGLEVEL=debug
ECS_CONTAINER_INSTANCE_TAGS=${tags}
ECS_ENABLE_TASK_IAM_ROLE=true
EOF
