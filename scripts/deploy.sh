#!/bin/bash
set -e

echo "== Pulling latest app code =="
cd ~/apps/168cap && git pull origin main
cd ~/apps/168port && git pull origin main
cd ~/apps/168board && git pull origin main

echo "== Rebuilding and restarting containers =="
cd ~/compose
docker-compose up -d --build

echo "== Deployment complete =="
