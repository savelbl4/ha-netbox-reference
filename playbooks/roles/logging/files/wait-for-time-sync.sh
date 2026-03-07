#!/bin/bash
set -euo pipefail
for i in $(seq 1 60); do
    if timedatectl show -p NTPSynchronized --value | grep -qx yes; then
        exit 0
    fi
    sleep 2
done
echo "Time sync did not become ready in time" >&2
exit 1
