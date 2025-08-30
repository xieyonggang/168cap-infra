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

# Function to validate module name
validate_module_name() {
    local name=$1
    if [[ ! $name =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi
    return 0
}

# Function to check if module exists in NGINX config
check_module_exists() {
    local module_name=$1
    local nginx_config="/etc/nginx/sites-available/168cap.com"
    
    if grep -q "location /apps/$module_name" "$nginx_config"; then
        return 0
    else
        return 1
    fi
}

# Function to get module port from NGINX config
get_module_port() {
    local module_name=$1
    local nginx_config="/etc/nginx/sites-available/168cap.com"
    
    # Extract port from proxy_pass line
    local port=$(grep -A 20 "location /apps/$module_name" "$nginx_config" | grep "proxy_pass" | grep -oE 'localhost:[0-9]+' | head -1 | cut -d: -f2)
    echo "$port"
}

# Main script
main() {
    print_status "🗑️  168cap Infrastructure - Remove Module App"
    echo "=================================================="
    
    # Check if running as root or with sudo access
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script needs sudo access for NGINX configuration"
        if ! sudo -n true 2>/dev/null; then
            print_error "Please run with sudo or ensure passwordless sudo is configured"
            exit 1
        fi
    fi
    
    # Check required commands
    local required_commands=("nginx" "docker" "docker-compose")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Get user input
    echo
    read -p "Enter module name to remove: " MODULE_NAME
    
    # Validate module name
    if [[ -z "$MODULE_NAME" ]]; then
        print_error "Module name is required"
        exit 1
    fi
    
    if ! validate_module_name "$MODULE_NAME"; then
        print_error "Invalid module name. Use only alphanumeric characters, hyphens, and underscores"
        exit 1
    fi
    
    # Check if module exists in NGINX config
    if ! check_module_exists "$MODULE_NAME"; then
        print_error "Module '$MODULE_NAME' not found in NGINX configuration"
        print_status "Available modules in NGINX config:"
        grep -oE 'location /apps/[^/]+' /etc/nginx/sites-available/168cap.com | sed 's/location \/apps\///' | sort -u
        exit 1
    fi
    
    # Get module port
    MODULE_PORT=$(get_module_port "$MODULE_NAME")
    MODULE_PATH="/apps/$MODULE_NAME"
    MODULE_DIR="$HOME/apps/module"
    
    print_status "Module details:"
    echo "  Module Name: $MODULE_NAME"
    echo "  Module Path: $MODULE_PATH"
    echo "  Module Port: $MODULE_PORT"
    echo "  Module Directory: $MODULE_DIR"
    echo
    
    # Confirm removal
    print_warning "⚠️  This will remove the module from NGINX configuration"
    print_warning "The module directory and files will NOT be deleted"
    echo
    
    read -p "Continue with removal? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Removal cancelled by user"
        exit 0
    fi
    
    # Step 1: Stop the module if it's running
    print_status "🛑 Stopping module if running..."
    if [[ -d "$MODULE_DIR" && -f "$MODULE_DIR/docker-compose.yml" ]]; then
        cd "$MODULE_DIR"
        if docker-compose ps | grep -q "Up"; then
            print_status "Stopping module containers..."
            docker-compose down
            print_success "Module containers stopped"
        else
            print_status "Module containers not running"
        fi
    else
        print_status "Module directory or docker-compose.yml not found, skipping container stop"
    fi
    
    # Step 2: Remove from NGINX configuration
    print_status "🌐 Removing module from NGINX configuration..."
    MAIN_NGINX_CONFIG="/etc/nginx/sites-available/168cap.com"
    
    # Create backup
    sudo cp "$MAIN_NGINX_CONFIG" "${MAIN_NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    print_success "NGINX config backed up"
    
    # Remove the module location blocks
    # Find the line numbers for the module configuration
    local start_line=$(grep -n "# Module: $MODULE_NAME" "$MAIN_NGINX_CONFIG" | cut -d: -f1)
    
    if [[ -n "$start_line" ]]; then
        # Find the end of the module configuration (next closing brace)
        local end_line=$(tail -n +$((start_line + 1)) "$MAIN_NGINX_CONFIG" | grep -n "^}" | head -1 | cut -d: -f1)
        end_line=$((start_line + end_line))
        
        # Remove the lines
        sudo sed -i "${start_line},${end_line}d" "$MAIN_NGINX_CONFIG"
        print_success "Removed module configuration from NGINX"
    else
        print_warning "Could not find exact module configuration, attempting pattern-based removal"
        
        # Fallback: remove lines containing the module path
        sudo sed -i "/location = \/apps\/$MODULE_NAME/d" "$MAIN_NGINX_CONFIG"
        sudo sed -i "/location \/apps\/$MODULE_NAME\//,/^}/d" "$MAIN_NGINX_CONFIG"
        print_success "Removed module configuration using pattern matching"
    fi
    
    # Test NGINX configuration
    print_status "Testing NGINX configuration..."
    if ! sudo nginx -t; then
        print_error "NGINX configuration test failed"
        print_warning "Restoring backup..."
        sudo cp "${MAIN_NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" "$MAIN_NGINX_CONFIG"
        exit 1
    fi
    
    sudo systemctl reload nginx
    print_success "NGINX configuration updated and reloaded"
    
    # Step 3: Check if port is still in use by other services
    print_status "🔍 Checking if port $MODULE_PORT is still in use..."
    if netstat -tuln | grep -q ":$MODULE_PORT "; then
        print_warning "Port $MODULE_PORT is still in use by another service"
        print_status "Active services on port $MODULE_PORT:"
        netstat -tuln | grep ":$MODULE_PORT "
    else
        print_success "Port $MODULE_PORT is now free"
    fi
    
    # Step 4: Optional cleanup of module directory
    echo
    print_warning "Module directory cleanup options:"
    echo "1. Keep module directory and files (recommended)"
    echo "2. Remove module directory completely"
    echo "3. Show module directory contents"
    echo
    
    read -p "Choose option (1-3, default 1): " CLEANUP_OPTION
    CLEANUP_OPTION=${CLEANUP_OPTION:-1}
    
    case $CLEANUP_OPTION in
        1)
            print_status "Keeping module directory: $MODULE_DIR"
            print_warning "You can manually delete it later if needed"
            ;;
        2)
            if [[ -d "$MODULE_DIR" ]]; then
                print_warning "⚠️  This will permanently delete the module directory and all its contents"
                read -p "Are you sure? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -rf "$MODULE_DIR"
                    print_success "Module directory removed: $MODULE_DIR"
                else
                    print_status "Keeping module directory"
                fi
            else
                print_status "Module directory does not exist"
            fi
            ;;
        3)
            if [[ -d "$MODULE_DIR" ]]; then
                print_status "Module directory contents:"
                ls -la "$MODULE_DIR"
                echo
                print_status "Directory size:"
                du -sh "$MODULE_DIR"
            else
                print_status "Module directory does not exist"
            fi
            ;;
        *)
            print_status "Invalid option, keeping module directory"
            ;;
    esac
    
    # Final status report
    echo
    print_success "🎉 Module removal completed successfully!"
    echo "=================================================="
    echo "Removed Module: $MODULE_NAME"
    echo "Module Path: $MODULE_PATH"
    echo "Module Port: $MODULE_PORT"
    echo
    print_status "What was done:"
    echo "✅ Removed NGINX configuration for $MODULE_PATH"
    echo "✅ Stopped module containers (if running)"
    echo "✅ Reloaded NGINX configuration"
    echo "✅ Created backup of NGINX config"
    echo
    print_status "Next steps:"
    echo "1. Test that other apps still work: https://168cap.com"
    echo "2. If you removed the module directory, it's gone permanently"
    echo "3. If you kept it, you can access it at: $MODULE_DIR"
    echo
    print_status "Useful commands:"
    echo "- Check NGINX status: sudo systemctl status nginx"
    echo "- View NGINX logs: sudo tail -f /var/log/nginx/error.log"
    echo "- List remaining modules: grep -oE 'location /apps/[^/]+' /etc/nginx/sites-available/168cap.com"
    echo
}

# Run main function
main "$@"
