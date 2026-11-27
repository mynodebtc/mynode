#!/bin/bash
# Runs after launching tunnelsats.service (ExecStartPost=+)
set -euo pipefail

echo "TunnelSats service started on 127.0.0.1:18739."
