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

# Function to validate module name
validate_module_name() {
    local name=$1
    if [[ ! $name =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
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
    print_status "🚀 168cap Infrastructure - Module App Setup"
    echo "================================================"
    
    # Check if running as root or with sudo access
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script needs sudo access for NGINX configuration"
        if ! sudo -n true 2>/dev/null; then
            print_error "Please run with sudo or ensure passwordless sudo is configured"
            exit 1
        fi
    fi
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "nginx" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Get user input
    echo
    read -p "Enter module name (e.g., myapp): " MODULE_NAME
    
    # Validate module name
    if [[ -z "$MODULE_NAME" ]]; then
        print_error "Module name is required"
        exit 1
    fi
    
    if ! validate_module_name "$MODULE_NAME"; then
        print_error "Invalid module name. Use only alphanumeric characters, hyphens, and underscores"
        exit 1
    fi
    
    # Check if module already exists
    MODULE_PATH="/apps/$MODULE_NAME"
    if [[ -d "$HOME/apps/$MODULE_NAME" ]]; then
        print_warning "Module directory already exists: $HOME/apps/$MODULE_NAME"
        read -p "Continue with existing directory? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Setup cancelled by user"
            exit 0
        fi
    fi
    
    # Get port information
    read -p "Enter the port your app runs on (default: 8000): " APP_PORT
    APP_PORT=${APP_PORT:-8000}
    
    # Get health check path
    read -p "Enter health check path [/health]: " HEALTH_PATH
    HEALTH_PATH=${HEALTH_PATH:-/health}
    
    # Get GitHub repository URL (optional)
    read -p "Enter GitHub repository URL (optional, press enter to skip): " REPO_URL
    
    # Sanitize module name for container/directory use
    SAFE_MODULE_NAME=$(echo "$MODULE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    
    print_status "Configuration:"
    echo "  Module Name: $MODULE_NAME"
    echo "  Safe Name: $SAFE_MODULE_NAME"
    echo "  Module Path: $MODULE_PATH"
    echo "  App Port: $APP_PORT"
    echo "  Health Check: $HEALTH_PATH"
    if [[ -n "$REPO_URL" ]]; then
        echo "  Repository: $REPO_URL"
    fi
    echo
    
    read -p "Continue with this configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi
    
    # Step 1: Clone repository if provided
    if [[ -n "$REPO_URL" ]]; then
        print_status "📥 Cloning repository..."
        mkdir -p "$HOME/apps"
        cd "$HOME/apps" || exit 1
        
        if [[ -d "$SAFE_MODULE_NAME/.git" ]]; then
            print_warning "Directory $SAFE_MODULE_NAME already exists. Pulling latest changes..."
            cd "$SAFE_MODULE_NAME"
            git pull origin main || git pull origin master || {
                print_warning "git pull failed; recloning repository..."
                cd "$HOME/apps"
                rm -rf "$SAFE_MODULE_NAME"
                git clone "$REPO_URL" "$SAFE_MODULE_NAME"
            }
            cd ..
        else
            git clone "$REPO_URL" "$SAFE_MODULE_NAME"
        fi
        
        print_success "Repository cloned to $HOME/apps/$SAFE_MODULE_NAME"
    else
        print_status "📁 Creating module directory..."
        mkdir -p "$HOME/apps/$SAFE_MODULE_NAME"
        print_success "Module directory created: $HOME/apps/$SAFE_MODULE_NAME"
    fi
    
    # Step 2: Check for existing docker-compose.yml in module
    MODULE_COMPOSE_FILE="$HOME/apps/$SAFE_MODULE_NAME/docker-compose.yml"
    if [[ -f "$MODULE_COMPOSE_FILE" ]]; then
        print_status "🐳 Found existing docker-compose.yml in module"
        print_warning "Please ensure your docker-compose.yml exposes port $APP_PORT"
        print_warning "You can start your module with: cd $HOME/apps/$SAFE_MODULE_NAME && docker-compose up -d"
    else
        print_warning "No docker-compose.yml found in module directory"
        print_warning "Please create one that exposes port $APP_PORT"
    fi
    
    # Step 3: Update main NGINX configuration to add module route
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
    
    # Check if module route already exists
    if grep -q "location $MODULE_PATH" "$MAIN_NGINX_CONFIG"; then
        print_warning "NGINX route for $MODULE_PATH already exists"
        read -p "Update existing route? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Skipping NGINX configuration update"
        else
            # Remove existing route
            sudo sed -i "/# Module: $MODULE_NAME/,/}/d" "$MAIN_NGINX_CONFIG"
        fi
    fi
    
    # Add module route to main config
    # Create a temporary file with the new location block
    TEMP_CONFIG=$(mktemp)
    
    # Add the new module location before the closing brace
    sed '/^}/i\
    # Module: '"$MODULE_NAME"'\
    location = '"$MODULE_PATH"' { return 301 '"$MODULE_PATH"'/; }\
    location '"$MODULE_PATH"'/ {\
        proxy_pass http://localhost:'"$APP_PORT"'/;\
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
    print_success "NGINX configuration updated"
    
    # Step 4: Create a simple start script for the module
    print_status "📝 Creating module management script..."
    MODULE_SCRIPT="$HOME/apps/$SAFE_MODULE_NAME/manage.sh"
    
    cat > "$MODULE_SCRIPT" << EOF
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

print_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

print_warning() {
    echo -e "\${YELLOW}[WARNING]\${NC} \$1"
}

print_error() {
    echo -e "\${RED}[ERROR]\${NC} \$1"
}

# Function to check if docker-compose.yml exists
check_compose_file() {
    if [[ ! -f "docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found in current directory"
        exit 1
    fi
}

# Function to check if app is running
check_app_running() {
    if docker-compose ps | grep -q "Up"; then
        return 0
    else
        return 1
    fi
}

case "\$1" in
    start)
        print_status "Starting $MODULE_NAME..."
        check_compose_file
        docker-compose up -d
        print_success "$MODULE_NAME started"
        print_status "Access at: https://168cap.com$MODULE_PATH"
        ;;
    stop)
        print_status "Stopping $MODULE_NAME..."
        check_compose_file
        docker-compose down
        print_success "$MODULE_NAME stopped"
        ;;
    restart)
        print_status "Restarting $MODULE_NAME..."
        check_compose_file
        docker-compose restart
        print_success "$MODULE_NAME restarted"
        ;;
    logs)
        print_status "Showing logs for $MODULE_NAME..."
        check_compose_file
        docker-compose logs -f
        ;;
    status)
        print_status "Status of $MODULE_NAME..."
        check_compose_file
        docker-compose ps
        ;;
    build)
        print_status "Building $MODULE_NAME..."
        check_compose_file
        docker-compose build --no-cache
        print_success "$MODULE_NAME built"
        ;;
    update)
        print_status "Updating $MODULE_NAME..."
        if [[ -d ".git" ]]; then
            git pull origin main || git pull origin master
            print_success "Code updated"
        else
            print_warning "Not a git repository, skipping code update"
        fi
        check_compose_file
        docker-compose build --no-cache
        docker-compose up -d
        print_success "$MODULE_NAME updated and restarted"
        ;;
    health)
        print_status "Checking health of $MODULE_NAME..."
        if check_app_running; then
            if curl -sf "http://localhost:$APP_PORT$HEALTH_PATH" > /dev/null; then
                print_success "Health check passed"
            else
                print_warning "Health check failed"
            fi
        else
            print_error "App is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|logs|status|build|update|health}"
        echo
        echo "Commands:"
        echo "  start   - Start the module"
        echo "  stop    - Stop the module"
        echo "  restart - Restart the module"
        echo "  logs    - Show logs"
        echo "  status  - Show status"
        echo "  build   - Build the module"
        echo "  update  - Update code and restart"
        echo "  health  - Check health status"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$MODULE_SCRIPT"
    print_success "Module management script created: $MODULE_SCRIPT"
    
    # Step 5: Create a README for the module
    print_status "📖 Creating module README..."
    MODULE_README="$HOME/apps/$SAFE_MODULE_NAME/README.md"
    
    cat > "$MODULE_README" << EOF
# $MODULE_NAME

This module is part of the 168cap infrastructure.

## Quick Start

\`\`\`bash
# Start the module
./manage.sh start

# Check status
./manage.sh status

# View logs
./manage.sh logs

# Stop the module
./manage.sh stop
\`\`\`

## Access

- **URL**: https://168cap.com$MODULE_PATH
- **Port**: $APP_PORT
- **Health Check**: $HEALTH_PATH

## Configuration

1. Ensure your \`docker-compose.yml\` exposes port \`$APP_PORT\`
2. Your app should be accessible at \`http://localhost:$APP_PORT\`
3. Health check endpoint should be at \`http://localhost:$APP_PORT$HEALTH_PATH\`

## Management Commands

- \`./manage.sh start\` - Start the module
- \`./manage.sh stop\` - Stop the module
- \`./manage.sh restart\` - Restart the module
- \`./manage.sh logs\` - Show logs
- \`./manage.sh status\` - Show status
- \`./manage.sh build\` - Build the module
- \`./manage.sh update\` - Update code and restart
- \`./manage.sh health\` - Check health status

## NGINX Configuration

The module is configured to be accessible at \`$MODULE_PATH\` through NGINX reverse proxy.

## Troubleshooting

1. Check if the module is running: \`./manage.sh status\`
2. View logs: \`./manage.sh logs\`
3. Check health: \`./manage.sh health\`
4. Restart if needed: \`./manage.sh restart\`
EOF
    
    print_success "Module README created: $MODULE_README"
    
    # Final status report
    echo
    print_success "🎉 Module setup completed successfully!"
    echo "================================================"
    echo "Module Name: $MODULE_NAME"
    echo "Module Path: $MODULE_PATH"
    echo "App Port: $APP_PORT"
    echo "Health Check: $HEALTH_PATH"
    echo "Module Directory: $HOME/apps/$SAFE_MODULE_NAME"
    echo
    print_status "Next steps:"
    echo "1. Navigate to module directory: cd $HOME/apps/$SAFE_MODULE_NAME"
    echo "2. Create or update your docker-compose.yml to expose port $APP_PORT"
    echo "3. Start your module: ./manage.sh start"
    echo "4. Test your app: https://168cap.com$MODULE_PATH"
    echo
    print_status "Useful commands:"
    echo "- Start module: cd $HOME/apps/$SAFE_MODULE_NAME && ./manage.sh start"
    echo "- View logs: cd $HOME/apps/$SAFE_MODULE_NAME && ./manage.sh logs"
    echo "- Check status: cd $HOME/apps/$SAFE_MODULE_NAME && ./manage.sh status"
    echo "- Update module: cd $HOME/apps/$SAFE_MODULE_NAME && ./manage.sh update"
    echo
    
    if [[ ! -f "$MODULE_COMPOSE_FILE" ]]; then
        print_warning "⚠️  Don't forget to create a docker-compose.yml file that exposes port $APP_PORT!"
    fi
}

# Run main function
main "$@"
