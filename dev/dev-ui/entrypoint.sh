#!/bin/bash
# Entrypoint for the mocked UI dev container.
set -e

# Build the fixture filesystem (device paths, marker files, fake binaries).
python3 /opt/mynode/dev/seed_fixture_fs.py

cd /opt/mynode/dev
exec python3 dev_server.py
