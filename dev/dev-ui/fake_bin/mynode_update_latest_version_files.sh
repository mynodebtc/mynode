#!/bin/bash
# Fake version of /usr/bin/mynode_update_latest_version_files.sh.
# Sources the real app version definitions (copied into /usr/share/mynode by
# the fixture seeder) and writes every <app>_version_latest file, exactly like
# the real script - but generically, so it never goes stale.
source /usr/share/mynode/mynode_app_versions.sh 2>/dev/null || exit 0

for file_var in $(compgen -A variable | grep '_LATEST_VERSION_FILE$'); do
    version_var="${file_var%_LATEST_VERSION_FILE}_VERSION"
    file="${!file_var}"
    version="${!version_var}"
    if [ -n "$file" ] && [ -n "$version" ]; then
        echo "$version" > "$file"
    fi
done
exit 0
