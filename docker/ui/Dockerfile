FROM python:3.11-slim-bookworm

# Install required system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpam0g-dev \
    curl \
    rsync \
    git \
    nano \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/mynode

# Copy and install Python requirements
COPY docker/ui/requirements-ui.txt /tmp/requirements-ui.txt
RUN pip install --no-cache-dir -r /tmp/requirements-ui.txt

EXPOSE 8000

ENV PYTHONPATH="/var/pynode:/var/www/mynode"
ENV MYNODE_UI_MOCK=1
ENV MYNODE_UI_SCENARIO=stable-synced
ENV MYNODE_UI_PORT=8000
ENV MYNODE_UI_RELOAD=1

COPY docker/ui/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
