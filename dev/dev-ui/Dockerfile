# Mocked UI dev container for the myNode web UI.
# Runs the real Flask app from the repo (volume-mounted read-only at the same
# paths used on a device) with a mock shim layer so no real backend is needed.
FROM python:3.11-slim-bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends procps && \
    rm -rf /var/lib/apt/lists/*

COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements-dev.txt

# Python path order matters:
#   1. /opt/mynode/dev             (dev server + dev blueprint)
#   2. /opt/mynode/dev/mock_pynode (shim layer - shadows pynode/www module names)
#   3. /var/www/mynode             (real Flask app)
#   4. /var/pynode                 (real backend library)
# This mirrors the pynode.pth mechanism used on a real device (setup_device.sh).
ENV PYTHONPATH=/opt/mynode/dev/mock_pynode:/var/www/mynode:/var/pynode \
    PYTHONUNBUFFERED=1

WORKDIR /opt/mynode/dev
CMD ["bash", "/opt/mynode/dev/entrypoint.sh"]
