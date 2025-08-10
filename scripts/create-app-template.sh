#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Main script
main() {
    print_status "🚀 168cap App Template Generator"
    echo "======================================"
    
    # Get user input
    echo
    read -p "Enter app name (e.g., 'my-chat-app'): " APP_NAME
    read -p "Enter app type (fastapi/streamlit) [fastapi]: " APP_TYPE
    APP_TYPE=${APP_TYPE:-fastapi}
    read -p "Enter target directory [./]: " TARGET_DIR
    TARGET_DIR=${TARGET_DIR:-./}
    
    # Validate inputs
    if [[ -z "$APP_NAME" ]]; then
        print_error "App name is required"
        exit 1
    fi
    
    if [[ "$APP_TYPE" != "fastapi" && "$APP_TYPE" != "streamlit" ]]; then
        print_error "App type must be 'fastapi' or 'streamlit'"
        exit 1
    fi
    
    # Sanitize app name
    SAFE_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    APP_DIR="$TARGET_DIR/$SAFE_APP_NAME"
    
    print_status "Configuration:"
    echo "  App Name: $APP_NAME"
    echo "  Safe Name: $SAFE_APP_NAME"
    echo "  App Type: $APP_TYPE"
    echo "  Directory: $APP_DIR"
    echo
    
    # Create app directory
    if [[ -d "$APP_DIR" ]]; then
        print_warning "Directory $APP_DIR already exists"
        read -p "Continue and overwrite files? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Template creation cancelled"
            exit 0
        fi
    else
        mkdir -p "$APP_DIR"
    fi
    
    # Get template directory
    SCRIPT_DIR=$(dirname "$(realpath "$0")")
    TEMPLATE_DIR="$SCRIPT_DIR/../templates"
    
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        print_error "Template directory not found: $TEMPLATE_DIR"
        exit 1
    fi
    
    # Copy base files
    print_status "📁 Creating app structure..."
    
    # Copy appropriate Dockerfile
    if [[ "$APP_TYPE" == "streamlit" ]]; then
        cp "$TEMPLATE_DIR/Dockerfile.streamlit" "$APP_DIR/Dockerfile"
    else
        cp "$TEMPLATE_DIR/Dockerfile.fastapi" "$APP_DIR/Dockerfile"
    fi
    
    # Copy other template files
    cp "$TEMPLATE_DIR/.env.example" "$APP_DIR/"
    cp "$TEMPLATE_DIR/requirements.txt" "$APP_DIR/"
    
    # Create main application file based on type
    if [[ "$APP_TYPE" == "streamlit" ]]; then
        # Create Streamlit app
        cat > "$APP_DIR/app.py" << EOF
"""
Streamlit app template for 168cap infrastructure
"""

import streamlit as st
import os
from datetime import datetime

# Page configuration
st.set_page_config(
    page_title="$APP_NAME",
    page_icon="🚀",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Main app
def main():
    st.title("$APP_NAME")
    st.markdown("Welcome to your 168cap LLM App!")
    
    # Sidebar
    with st.sidebar:
        st.header("Settings")
        st.write(f"Environment: {os.getenv('ENVIRONMENT', 'development')}")
        st.write(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Main content
    st.header("Chat Interface")
    
    # Initialize chat history
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    # Display chat messages
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
    
    # Chat input
    if prompt := st.chat_input("What can I help you with?"):
        # Add user message to chat history
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)
        
        # Generate response (customize with your LLM logic)
        with st.chat_message("assistant"):
            response = f"Echo: {prompt}"  # Replace with actual LLM response
            st.markdown(response)
        
        # Add assistant response to chat history
        st.session_state.messages.append({"role": "assistant", "content": response})

if __name__ == "__main__":
    main()
EOF
    else
        # Copy FastAPI template
        cp "$TEMPLATE_DIR/main.py" "$APP_DIR/"
    fi
    
    # Create README
    cat > "$APP_DIR/README.md" << EOF
# $APP_NAME

$APP_TYPE application running on 168cap infrastructure.

## Setup

1. Install dependencies:
   \`\`\`bash
   pip install -r requirements.txt
   \`\`\`

2. Copy and configure environment variables:
   \`\`\`bash
   cp .env.example .env
   # Edit .env with your actual values
   \`\`\`

3. Run locally:
   \`\`\`bash
EOF
    
    if [[ "$APP_TYPE" == "streamlit" ]]; then
        cat >> "$APP_DIR/README.md" << EOF
   streamlit run app.py --server.port 8000
   \`\`\`

## Deployment

This app is configured to run on the 168cap infrastructure. Make sure:

- App runs on port 8000
- Health check endpoint is available at \`/_stcore/health\`
- Environment variables are configured in \`.env\`

## Health Check

Streamlit apps use the built-in health check at \`/_stcore/health\`.
EOF
    else
        cat >> "$APP_DIR/README.md" << EOF
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   \`\`\`

## API Endpoints

- \`GET /\` - Root endpoint
- \`GET /health\` - Health check
- \`GET /api/info\` - App information
- \`POST /api/chat\` - Chat endpoint (customize as needed)

## Deployment

This app is configured to run on the 168cap infrastructure. Make sure:

- App runs on port 8000
- Health check endpoint is available at \`/health\`
- Environment variables are configured in \`.env\`
EOF
    fi
    
    # Create .gitignore
    cat > "$APP_DIR/.gitignore" << EOF
# Environment variables
.env

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# IDEs
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Temporary files
tmp/
temp/
EOF
    
    # Make .env from template and customize
    sed -i "s/Your App Name/$APP_NAME/g" "$APP_DIR/.env.example"
    
    print_success "✅ App template created successfully!"
    echo "======================================"
    echo "Location: $APP_DIR"
    echo "Type: $APP_TYPE"
    echo
    print_status "Next steps:"
    echo "1. cd $APP_DIR"
    echo "2. cp .env.example .env"
    echo "3. Edit .env with your actual values"
    echo "4. pip install -r requirements.txt"
    if [[ "$APP_TYPE" == "streamlit" ]]; then
        echo "5. streamlit run app.py --server.port 8000"
    else
        echo "5. uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
    fi
    echo
    print_status "To deploy to 168cap infrastructure:"
    echo "1. Push your app to GitHub"
    echo "2. Run: ~/168cap-infra/scripts/add-new-app.sh"
    echo
}

main "$@"