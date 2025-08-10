#!/bin/bash
if [ -z "$1" ]; then
  echo "Restarting all containers..."
  docker-compose restart
else
  echo "Restarting container: $1"
  docker-compose restart "$1"
fi
