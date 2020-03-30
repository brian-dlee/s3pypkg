#!/usr/bin/env bash
set -e
install_path=${INSTALL_PREFIX:-/usr/local/bin}/s3pypkg
curl "https://gist.githubusercontent.com/brian-dlee/d36fab4f80688ec9af0ba3bb5efe02d6/raw/5e50677b54c563d5b9428c91b2f8174702f8521d/s3pypkg" -o "$install_path"
chmod +x "$install_path"
echo "Successfully installed $(basename $install_path) at $install_path"
