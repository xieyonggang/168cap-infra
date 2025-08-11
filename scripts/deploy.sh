#!/bin/bash
set -e

echo "== Pulling latest app code =="
cd ~/apps/168cap && git pull origin main
cd ~/apps/168board && git pull origin main

echo "== Pulling latest infra repo (compose/nginx) =="
cd ~/168cap-infra && git pull origin main

echo "== Rebuilding and restarting containers =="
cd ~/168cap-infra/compose
docker-compose up -d --build

echo "== Deployment complete =="
