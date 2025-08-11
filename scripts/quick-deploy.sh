#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Quick deployment with minimal questions
main() {
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 <github-repo-url> [health-path]"
        print_error "Example: $0 https://github.com/yourusername/my-chat-app"
        print_error "Example: $0 https://github.com/yourusername/my-chat-app /docs"
        exit 1
    fi
    
    REPO_URL="$1"
    HEALTH_PATH="${2:-/health}"
    
    # Extract repo name
    if [[ $REPO_URL =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        GITHUB_USER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]%.git}"
        APP_NAME="$REPO_NAME"
        SUBDOMAIN="${REPO_NAME}.168cap.com"
        SSH_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
    else
        print_error "Invalid GitHub URL"
        exit 1
    fi
    
    print_status "🚀 Quick deploying: $APP_NAME → https://$SUBDOMAIN"
    
    # Get next port
    COMPOSE_FILE="$HOME/168cap-infra/compose/docker-compose.yml"
    EXTERNAL_PORT=$(grep -oE '"[0-9]+:8000"' "$COMPOSE_FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
    EXTERNAL_PORT=$((${EXTERNAL_PORT:-7999} + 1))
    
    SAFE_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    CONTAINER_NAME=$(echo "$SAFE_APP_NAME" | tr '-' '_')
    
    # Clone/update app via SSH with reclone fallback
    mkdir -p "$HOME/apps"
    cd "$HOME/apps"
    if [[ -d "$SAFE_APP_NAME/.git" ]]; then
        print_status "Updating existing app..."
        if ! (cd "$SAFE_APP_NAME" && git pull origin main || git pull origin master); then
            print_warning "git pull failed; recloning repository..."
            rm -rf "$SAFE_APP_NAME"
            git clone "$SSH_URL" "$SAFE_APP_NAME"
        fi
    else
        print_status "Cloning new app..."
        git clone "$SSH_URL" "$SAFE_APP_NAME"
    fi
    
    # Create basic .env if none exists
    if [[ ! -f "$HOME/apps/$SAFE_APP_NAME/.env" ]]; then
        if [[ -f "$HOME/apps/$SAFE_APP_NAME/.env.example" ]]; then
            cp "$HOME/apps/$SAFE_APP_NAME/.env.example" "$HOME/apps/$SAFE_APP_NAME/.env"
        else
            echo "APP_NAME=$APP_NAME" > "$HOME/apps/$SAFE_APP_NAME/.env"
        fi
    fi
    
    # Add to docker-compose
    if ! grep -q "$SAFE_APP_NAME:" "$COMPOSE_FILE"; then
        cat >> "$COMPOSE_FILE" << EOF

  $SAFE_APP_NAME:
    build: ../apps/$SAFE_APP_NAME
    container_name: $CONTAINER_NAME
    restart: always
    ports:
      - "$EXTERNAL_PORT:8000"
    env_file:
      - ../apps/$SAFE_APP_NAME/.env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000$HEALTH_PATH"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    fi
    
    # Create NGINX config
    print_status "Creating NGINX configuration..."
    sudo tee "/etc/nginx/sites-available/$SUBDOMAIN" > /dev/null << EOF
server {
    listen 80;
    server_name $SUBDOMAIN;
    location / {
        proxy_pass http://localhost:$EXTERNAL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    sudo ln -sf "/etc/nginx/sites-available/$SUBDOMAIN" "/etc/nginx/sites-enabled/"
    sudo nginx -t && sudo systemctl reload nginx
    
    # Deploy
    cd ~/168cap-infra/compose
    docker-compose up -d --build "$SAFE_APP_NAME"
    
    # Wait and test
    print_status "Waiting for container..."
    sleep 15
    
    if curl -sf "http://localhost:$EXTERNAL_PORT$HEALTH_PATH" > /dev/null; then
        # Get SSL
        print_status "Setting up SSL..."
        
        # Check for known problematic domains (DNSSEC issues)
        if [[ "$SUBDOMAIN" == "168cap.com" || "$SUBDOMAIN" == "www.168cap.com" ]]; then
            print_warning "⚠️  Skipping SSL for $SUBDOMAIN due to known DNSSEC issues"
            print_warning "    Fix DNSSEC in domain registrar, then run:"
            print_warning "    sudo certbot --nginx -d $SUBDOMAIN"
            print_success "🎉 Deployed: http://$SUBDOMAIN"
        else
            if sudo certbot --nginx -d "$SUBDOMAIN" --non-interactive --agree-tos --email "admin@168cap.com" --redirect; then
                print_success "🎉 Deployed: https://$SUBDOMAIN"
            else
                print_warning "⚠️  SSL setup failed. Common issues:"
                print_warning "    1. DNSSEC problems - check domain registrar settings"
                print_warning "    2. DNS not propagated - wait 24-48 hours"  
                print_warning "    3. Run manually: sudo certbot --nginx -d $SUBDOMAIN"
                print_success "🎉 Deployed: http://$SUBDOMAIN (SSL failed)"
            fi
        fi
    else
        print_error "❌ Deployment failed - check logs: docker-compose logs $SAFE_APP_NAME"
        exit 1
    fi

    # Update deploy.sh to include resilient pull for this app
    DEPLOY_SCRIPT="$HOME/168cap-infra/scripts/deploy.sh"
    cd "$HOME/168cap-infra"
    if ! git pull origin main; then
        print_warning "git pull failed for 168cap-infra; refreshing deploy.sh from origin/main"
        rm -f "$DEPLOY_SCRIPT"
        git fetch origin main || true
        git checkout origin/main -- scripts/deploy.sh || true
    fi
    chmod +x "$DEPLOY_SCRIPT"
    if ! grep -q "cd ~/apps/$SAFE_APP_NAME && git pull" "$DEPLOY_SCRIPT"; then
        sed -i "/^cd ~\\/168cap-infra\\/compose/i cd ~\/apps\/$SAFE_APP_NAME && git pull origin main || { rm -rf ~\/apps\/$SAFE_APP_NAME; git clone $SSH_URL ~\/apps\/$SAFE_APP_NAME; }" "$DEPLOY_SCRIPT"
        print_success "Added app pull step to deploy.sh"
    else
        print_status "deploy.sh already contains app pull step for $SAFE_APP_NAME"
    fi
}

main "$@"