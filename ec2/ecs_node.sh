#!/bin/bash

# Register instance to ECS cluster
cat <<'EOF' >> /etc/ecs/ecs.config
ECS_CLUSTER=${name}
ECS_LOGLEVEL=debug
ECS_CONTAINER_INSTANCE_TAGS=${tags}
ECS_ENABLE_TASK_IAM_ROLE=true
EOF
