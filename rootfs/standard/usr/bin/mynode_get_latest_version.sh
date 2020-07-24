#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh

torify wget $LATEST_VERSION_URL -O /usr/share/mynode/latest_version || \
    ( sleep 1s && torify wget $LATEST_VERSION_URL -O /usr/share/mynode/latest_version ) || \
    ( sleep 1s && wget $LATEST_VERSION_URL -O /usr/share/mynode/latest_version )

torify wget $LATEST_BETA_VERSION_URL -O /usr/share/mynode/latest_beta_version || \
    ( sleep 1s && torify wget $LATEST_BETA_VERSION_URL -O /usr/share/mynode/latest_beta_version ) || \
    ( sleep 1s && wget $LATEST_BETA_VERSION_URL -O /usr/share/mynode/latest_beta_version )