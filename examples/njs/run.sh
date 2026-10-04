#!/usr/bin/env bash
# Serve dist/handler.js with nginx and njs on 127.0.0.1:8196.
set -euo pipefail
cd "$(dirname "$0")"
docker run --rm --name eyg-njs -p 127.0.0.1:8196:8080 \
  -v "$PWD/conf/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$PWD/dist:/etc/nginx/njs:ro" \
  nginx:1.29-alpine
