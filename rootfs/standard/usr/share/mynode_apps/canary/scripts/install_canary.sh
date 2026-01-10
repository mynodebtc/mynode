#!/bin/bash
set -e

echo "Pulling Canary Docker images..."
docker pull schjonhaug/canary-backend:v1.3.0
docker pull schjonhaug/canary-frontend:v1.3.0

echo "Creating data directory..."
mkdir -p /mnt/hdd/mynode/canary
chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "Canary installation complete."
