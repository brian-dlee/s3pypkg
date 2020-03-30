#!/usr/bin/env bash
set -e
install_path=${INSTALL_PREFIX:-/usr/local/bin}/s3pypkg
curl "https://github.com/brian-dlee/s3pypkg/blob/master/s3pypkg.sh" -o "$install_path"
chmod +x "$install_path"
echo "Successfully installed $(basename $install_path) at $install_path"
