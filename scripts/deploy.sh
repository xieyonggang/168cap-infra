#!/bin/bash
set -euo pipefail

MODULES_ARG=${1:-all}

echo "== Deploy selector: $MODULES_ARG =="

# Normalize modules list
if [ "$MODULES_ARG" = "all" ] || [ "$MODULES_ARG" = "ALL" ]; then
  MODULES=(168cap 168board 168port)
else
  IFS=',' read -ra RAW <<< "$MODULES_ARG"
  MODULES=()
  for m in "${RAW[@]}"; do
    m_trim=$(echo "$m" | xargs)
    [ -n "$m_trim" ] && MODULES+=("$m_trim")
  done
fi

echo "== Modules to deploy: ${MODULES[*]} =="

echo "== Pulling latest infra repo (compose/nginx) =="
cd ~/168cap-infra && git pull origin main

echo "== Pulling latest app code =="
for app in "${MODULES[@]}"; do
  if [ -d "$HOME/apps/$app" ]; then
    echo "-- Updating $app"
    cd "$HOME/apps/$app" && git pull origin main
  else
    echo "-- Skipping $app (directory not found at $HOME/apps/$app)"
  fi
done

echo "== Rebuilding and restarting selected containers =="
cd ~/168cap-infra/compose

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "No modules specified; exiting."
  exit 0
fi

docker-compose build "${MODULES[@]}"
docker-compose up -d "${MODULES[@]}"

echo "== Deployment complete =="
