#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get next available port
get_next_port() {
    local compose_file="$HOME/168cap-infra/compose/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        echo "8000"
        return
    fi
    
    local max_port=$(grep -oE '"[0-9]+:8000"' "$compose_file" | grep -oE '[0-9]+' | sort -n | tail -1)
    if [[ -z "$max_port" ]]; then
        echo "8000"
    else
        echo $((max_port + 1))
    fi
}

# Function to validate app path
validate_app_path() {
    local path=$1
    if [[ ! $path =~ ^/apps/[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi
    return 0
}

# Function to check if port is available
check_port_available() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# Main script
main() {
    print_status "🚀 168cap Infrastructure - New App Setup Automation"
    echo "=================================================="
    
    # Check if running as root or with sudo access
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script needs sudo access for NGINX and SSL configuration"
        if ! sudo -n true 2>/dev/null; then
            print_error "Please run with sudo or ensure passwordless sudo is configured"
            exit 1
        fi
    fi
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "nginx" "certbot" "git" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Get user input
    echo
    read -p "Enter GitHub repository URL: " REPO_URL
    read -p "Enter internal health check path [/health]: " HEALTH_PATH
    HEALTH_PATH=${HEALTH_PATH:-/health}
    
    # Validate inputs
    if [[ -z "$REPO_URL" ]]; then
        print_error "GitHub repository URL is required"
        exit 1
    fi
    
    # Extract app name from GitHub URL
    # Supports formats: https://github.com/username/repo-name or git@github.com:username/repo-name.git
    if [[ $REPO_URL =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        GITHUB_USER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
        # Remove .git suffix if present
        REPO_NAME=${REPO_NAME%.git}
    else
        print_error "Invalid GitHub URL format. Use: https://github.com/username/repo-name"
        exit 1
    fi
    
    # Use repo name as app name and generate app path
    APP_NAME="$REPO_NAME"
    APP_PATH="/apps/${REPO_NAME}"
    
    # Ask for confirmation or allow override
    echo
    print_status "Extracted configuration:"
    echo "  Repository: $REPO_URL"
    echo "  App Name: $APP_NAME"
    echo "  App Path: $APP_PATH"
    echo
    
    read -p "Use different app path? (press enter to keep '$APP_PATH' or type new one): " CUSTOM_APP_PATH
    if [[ -n "$CUSTOM_APP_PATH" ]]; then
        # Ensure path starts with /apps/
        if [[ ! "$CUSTOM_APP_PATH" =~ ^/apps/ ]]; then
            CUSTOM_APP_PATH="/apps${CUSTOM_APP_PATH#/}"
        fi
        APP_PATH="$CUSTOM_APP_PATH"
        if ! validate_app_path "$APP_PATH"; then
            print_error "Invalid app path format: $APP_PATH (must be /apps/[name] with alphanumeric characters, hyphens, or underscores)"
            exit 1
        fi
    fi
    
    # Sanitize app name for container/directory use
    SAFE_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    CONTAINER_NAME=$(echo "$SAFE_APP_NAME" | tr '-' '_')
    
    # Get next available port
    EXTERNAL_PORT=$(get_next_port)
    
    print_status "Configuration:"
    echo "  App Name: $APP_NAME"
    echo "  Safe Name: $SAFE_APP_NAME"
    echo "  Container: ${CONTAINER_NAME}"
    echo "  App Path: $APP_PATH"
    echo "  Port: $EXTERNAL_PORT"
    echo "  Health Check: $HEALTH_PATH"
    echo "  Repository: $REPO_URL"
    echo
    
    read -p "Continue with this configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi
    
    # Check if port is available
    if ! check_port_available "$EXTERNAL_PORT"; then
        print_error "Port $EXTERNAL_PORT is already in use"
        exit 1
    fi
    
    # Step 1: Clone repository via SSH into ~/apps
    print_status "📥 Cloning repository via SSH..."
    SSH_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
    mkdir -p "$HOME/apps"
    cd "$HOME/apps" || exit 1
    
    if [[ -d "$SAFE_APP_NAME/.git" ]]; then
        print_warning "Directory $SAFE_APP_NAME already exists. Pulling latest changes..."
        cd "$SAFE_APP_NAME"
        git pull origin main || git pull origin master || {
          print_warning "git pull failed; recloning repository..."
          cd "$HOME/apps"
          rm -rf "$SAFE_APP_NAME"
          git clone "$SSH_URL" "$SAFE_APP_NAME"
        }
        cd ..
    else
        git clone "$SSH_URL" "$SAFE_APP_NAME"
    fi
    
    # Step 2: Create .env file if .env.example exists
    print_status "⚙️ Setting up environment file..."
    cd "$HOME/apps/$SAFE_APP_NAME"
    
    if [[ -f ".env.example" && ! -f ".env" ]]; then
        cp .env.example .env
        print_warning "Created .env from template. Please edit it with actual values:"
        print_warning "nano $HOME/apps/$SAFE_APP_NAME/.env"
    elif [[ ! -f ".env" ]]; then
        # Create basic .env file
        cat > .env << EOF
# Generated by add-new-app.sh
APP_NAME=$APP_NAME
DEBUG=false
LOG_LEVEL=info

# Add your environment variables here
# OPENAI_API_KEY=your_key_here
# DATABASE_URL=your_db_url_here
EOF
        print_warning "Created basic .env file. Please edit with your variables:"
        print_warning "nano $HOME/apps/$SAFE_APP_NAME/.env"
    fi
    
    # Step 3: Update docker-compose.yml
    print_status "🐳 Updating Docker Compose configuration..."
    COMPOSE_FILE="$HOME/168cap-infra/compose/docker-compose.yml"
    
    # Backup original file
    cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add new service to docker-compose.yml
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
    
    print_success "Added service to docker-compose.yml"
    
    # Step 4: Update main NGINX configuration to add app route
    print_status "🌐 Updating NGINX configuration..."
    MAIN_NGINX_CONFIG="/etc/nginx/sites-available/168cap.com"
    
    # Check if main config exists, if not create it
    if [[ ! -f "$MAIN_NGINX_CONFIG" ]]; then
        sudo tee "$MAIN_NGINX_CONFIG" > /dev/null << EOF
server {
    listen 80;
    server_name 168cap.com www.168cap.com;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Root location
    location / {
        return 200 "168cap Infrastructure - Apps available at /apps/[app-name]";
        add_header Content-Type text/plain;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF
        sudo ln -sf "$MAIN_NGINX_CONFIG" "/etc/nginx/sites-enabled/168cap.com"
    fi
    
    # Add app route to main config
    # Create a temporary file with the new location block
    TEMP_CONFIG=$(mktemp)
    
    # Add the new app location before the closing brace
    sed '/^}/i\
    # App: '"$APP_NAME"'\
    location '"$APP_PATH"' {\
        proxy_pass http://localhost:'"$EXTERNAL_PORT"';\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade \$http_upgrade;\
        proxy_set_header Connection '\''upgrade'\'';\
        proxy_set_header Host \$host;\
        proxy_set_header X-Real-IP \$remote_addr;\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto \$scheme;\
        proxy_cache_bypass \$http_upgrade;\
        \
        # Timeouts\
        proxy_connect_timeout 60s;\
        proxy_send_timeout 60s;\
        proxy_read_timeout 60s;\
        \
        # Buffer settings\
        proxy_buffering on;\
        proxy_buffer_size 128k;\
        proxy_buffers 4 256k;\
        proxy_busy_buffers_size 256k;\
    }\
    \
    location '"$APP_PATH"'/ {\
        proxy_pass http://localhost:'"$EXTERNAL_PORT"'/;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade \$http_upgrade;\
        proxy_set_header Connection '\''upgrade'\'';\
        proxy_set_header Host \$host;\
        proxy_set_header X-Real-IP \$remote_addr;\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto \$scheme;\
        proxy_cache_bypass \$http_upgrade;\
        \
        # Timeouts\
        proxy_connect_timeout 60s;\
        proxy_send_timeout 60s;\
        proxy_read_timeout 60s;\
        \
        # Buffer settings\
        proxy_buffering on;\
        proxy_buffer_size 128k;\
        proxy_buffers 4 256k;\
        proxy_busy_buffers_size 256k;\
    }' "$MAIN_NGINX_CONFIG" > "$TEMP_CONFIG"
    
    # Replace original with updated config
    sudo cp "$TEMP_CONFIG" "$MAIN_NGINX_CONFIG"
    rm "$TEMP_CONFIG"
    
    # Test NGINX configuration
    print_status "Testing NGINX configuration..."
    if ! sudo nginx -t; then
        print_error "NGINX configuration test failed"
        exit 1
    fi
    
    sudo systemctl reload nginx
    print_success "NGINX configuration created and enabled"
    
    # Step 5: Build and start the container
    print_status "🏗️ Building and starting container..."
    cd "$HOME/168cap-infra/compose"
    
    # Build the new service
    if ! docker-compose build "$SAFE_APP_NAME"; then
        print_error "Failed to build Docker container"
        exit 1
    fi
    
    # Start the new service
    if ! docker-compose up -d "$SAFE_APP_NAME"; then
        print_error "Failed to start Docker container"
        exit 1
    fi
    
    print_success "Container built and started"
    
    # Step 6: Wait for container to be healthy and test
    print_status "🔍 Testing container health..."
    sleep 10
    
    # Test internal connectivity
    MAX_ATTEMPTS=30
    ATTEMPT=0
    while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
        if curl -sf "http://localhost:$EXTERNAL_PORT$HEALTH_PATH" > /dev/null; then
            break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        print_status "Waiting for container to be ready... ($ATTEMPT/$MAX_ATTEMPTS)"
        sleep 2
    done
    
    if [[ $ATTEMPT -ge $MAX_ATTEMPTS ]]; then
        print_error "Container health check failed after $MAX_ATTEMPTS attempts"
        print_warning "Check container logs: docker-compose logs $SAFE_APP_NAME"
        exit 1
    fi
    
    print_success "Container is healthy"
    
    # Step 7: Test HTTP connectivity
    print_status "🌐 Testing HTTP connectivity..."
    if curl -sf "http://168cap.com$APP_PATH$HEALTH_PATH" > /dev/null; then
        print_success "HTTP connectivity working"
    else
        print_warning "HTTP test failed. This might be normal if DNS hasn't propagated yet."
    fi
    
    # Step 8: Setup SSL certificate (only for main domain if not already done)
    print_status "🔒 Checking SSL certificate..."
    if [[ ! -f "/etc/letsencrypt/live/168cap.com/fullchain.pem" ]]; then
        if sudo certbot --nginx -d "168cap.com" -d "www.168cap.com" --non-interactive --agree-tos --email "admin@168cap.com" --redirect; then
            print_success "SSL certificate obtained and configured"
        else
            print_warning "SSL certificate setup failed. You can run this manually later:"
            print_warning "sudo certbot --nginx -d 168cap.com -d www.168cap.com"
        fi
    else
        print_success "SSL certificate already exists for 168cap.com"
    fi
    
    # Test HTTPS
    sleep 5
    if curl -sf "https://168cap.com$APP_PATH$HEALTH_PATH" > /dev/null; then
        print_success "HTTPS connectivity working"
    else
        print_warning "HTTPS test failed. Certificate might need time to propagate."
    fi
    
    # Step 9: Ensure deploy.sh is up to date and includes this app
    print_status "📝 Updating deployment script..."
    DEPLOY_SCRIPT="$HOME/168cap-infra/scripts/deploy.sh"

    # Refresh deploy.sh from origin if local pull fails
    cd "$HOME/168cap-infra"
    if ! git pull origin main; then
        print_warning "git pull failed for 168cap-infra; refreshing deploy.sh from origin/main"
        rm -f "$DEPLOY_SCRIPT"
        git fetch origin main || true
        git checkout origin/main -- scripts/deploy.sh || true
    fi
    chmod +x "$DEPLOY_SCRIPT"

    # Inject idempotent app pull step before compose build/up
    if ! grep -q "cd ~/apps/$SAFE_APP_NAME && git pull" "$DEPLOY_SCRIPT"; then
        sed -i "/^cd ~\\/168cap-infra\\/compose/i cd ~\/apps\/$SAFE_APP_NAME && git pull origin main || { rm -rf ~\/apps\/$SAFE_APP_NAME; git clone git@github.com:${GITHUB_USER}\/${REPO_NAME}.git ~\/apps\/$SAFE_APP_NAME; }" "$DEPLOY_SCRIPT"
        print_success "Added app pull step to deploy.sh"
    else
        print_status "deploy.sh already contains app pull step for $SAFE_APP_NAME"
    fi
    
    # Final status report
    echo
    print_success "🎉 App setup completed successfully!"
    echo "=================================================="
    echo "App Name: $APP_NAME"
    echo "Container: $CONTAINER_NAME"
    echo "App URL: https://168cap.com$APP_PATH"
    echo "Port: $EXTERNAL_PORT"
    echo "Health Check: $HEALTH_PATH"
    echo
    print_status "Next steps:"
    echo "1. Edit environment variables: nano $HOME/apps/$SAFE_APP_NAME/.env"
    echo "2. Test your app: https://168cap.com$APP_PATH"
    echo "3. Check container logs: docker-compose logs -f $SAFE_APP_NAME"
    echo "4. Monitor resources: docker stats"
    echo
    print_status "Useful commands:"
    echo "- Restart app: docker-compose restart $SAFE_APP_NAME"
    echo "- View logs: docker-compose logs -f $SAFE_APP_NAME"
    echo "- Rebuild: docker-compose build --no-cache $SAFE_APP_NAME && docker-compose up -d $SAFE_APP_NAME"
    echo "- Remove app: docker-compose down $SAFE_APP_NAME"
    echo
    
    if [[ -f "$HOME/apps/$SAFE_APP_NAME/.env" ]]; then
        print_warning "⚠️  Don't forget to configure your .env file with actual values!"
    fi
}

# Run main function
main "$@"