#!/bin/bash
set -e

echo "== Pulling latest app code =="
cd ~/apps/port-app && git pull origin main
cd ~/apps/chat-app && git pull origin main

echo "== Rebuilding and restarting containers =="
cd ~/compose
docker-compose up -d --build

echo "== Deployment complete =="
