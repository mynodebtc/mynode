#!/bin/bash
echo "Stopping Canary containers..."
docker stop canary canary-frontend 2>/dev/null || true
docker rm canary canary-frontend 2>/dev/null || true

echo "Removing Docker images..."
docker rmi schjonhaug/canary-backend:v1.3.0 2>/dev/null || true
docker rmi schjonhaug/canary-frontend:v1.3.0 2>/dev/null || true

echo "Removing data directory..."
rm -rf /mnt/hdd/mynode/canary

echo "Canary uninstalled."
