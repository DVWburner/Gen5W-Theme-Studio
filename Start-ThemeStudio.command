#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    echo "Install Docker Desktop for Mac, open it, then run this launcher again."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "Start Docker Desktop, wait for it to finish starting, then run this launcher again."
    exit 1
fi

trap 'docker compose down' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker compose up --build --detach --wait
open "http://localhost:8470/"
echo "Keep this window open. Press Ctrl+C to stop Theme Studio."
docker compose logs --follow
