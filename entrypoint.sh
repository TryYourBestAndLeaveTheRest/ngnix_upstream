#!/bin/sh

# Determine backup pool based on active pool
if [ "$ACTIVE_POOL" = "blue" ]; then
    export BACKUP_POOL="green"
else
    export BACKUP_POOL="blue"
fi

echo "Active Pool: $ACTIVE_POOL"
echo "Backup Pool: $BACKUP_POOL"

# Substitute environment variables in nginx config
envsubst '${ACTIVE_POOL} ${BACKUP_POOL}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Validate nginx config
nginx -t

# Execute the CMD
exec "$@"
