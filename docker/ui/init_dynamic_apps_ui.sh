#!/bin/bash
set -e

echo "Initializing dynamic apps for UI-only mock mode..."

# Ensure target directories exist
mkdir -p /var/www/mynode/app
mkdir -p /var/www/mynode/templates/app
mkdir -p /var/www/mynode/static/images/app_icons
mkdir -p /var/www/mynode/static/images/screenshots

# Loop through each dynamic app
for app_dir in /usr/share/mynode_apps/*; do
    if [ -d "$app_dir" ]; then
        app_name=$(basename "$app_dir")
        echo "Processing dynamic app: $app_name"

        # Install python web files
        if [ -d "$app_dir/www/python" ]; then
            mkdir -p "/var/www/mynode/app/$app_name"
            cp -f "$app_dir/www/python"/*.py "/var/www/mynode/app/$app_name/" 2>/dev/null || true
        fi

        # Install template web files
        if [ -d "$app_dir/www/templates" ]; then
            mkdir -p "/var/www/mynode/templates/app/$app_name"
            cp -f "$app_dir/www/templates"/*.html "/var/www/mynode/templates/app/$app_name/" 2>/dev/null || true
        fi

        # Install App Icon
        if [ -f "$app_dir/$app_name.png" ]; then
            cp -f "$app_dir/$app_name.png" "/var/www/mynode/static/images/app_icons/$app_name.png"
        fi

        # Install Screenshots
        if [ -d "$app_dir/screenshots" ]; then
            mkdir -p "/var/www/mynode/static/images/screenshots/$app_name"
            cp -f "$app_dir/screenshots"/*.png "/var/www/mynode/static/images/screenshots/$app_name/" 2>/dev/null || true
        fi
    fi
done

echo "Dynamic apps initialized successfully."
