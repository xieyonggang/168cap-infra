# 168cap-infra

Complete infrastructure setup for hosting 168cap.com and multiple LLM applications on a single DigitalOcean droplet (2GB RAM) using Docker Compose with NGINX reverse proxy.

## Overview

This setup allows you to:
- Host your main website (168cap.com) and multiple LLM apps on one droplet
- Use NGINX as a reverse proxy to route traffic to different Docker containers
- Each app runs in its own Docker container with individual Dockerfiles
- Automatic SSL certificates with Let's Encrypt
- CI/CD deployment via GitHub Actions

## Initial DigitalOcean Droplet Setup

### 1. Create Droplet
- **Size**: Basic droplet, 2GB RAM, 1 vCPU ($12/month)
- **OS**: Ubuntu 22.04 LTS
- **Region**: Choose closest to your users
- **Authentication**: SSH keys (recommended) or password

### 2. Initial Server Configuration
```bash
# Connect to your droplet
ssh root@your_droplet_ip

# Update system packages
apt update && apt upgrade -y

# Create non-root user (optional but recommended)
adduser yonggangx
usermod -aG sudo yonggangx
```

### 3. Install Required Software
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker $USER

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install NGINX
apt install nginx -y

# Install Certbot for SSL certificates
apt install certbot python3-certbot-nginx -y

# Install Git
apt install git -y

# Restart to apply group changes
logout
# SSH back in
```

### 4. Configure Firewall
```bash
# Enable UFW firewall
ufw enable

# Allow SSH, HTTP, and HTTPS
ufw allow ssh
ufw allow 80
ufw allow 443

# Check status
ufw status
```

## Domain and DNS Setup

### 1. Point Your Domains to Droplet
In your domain registrar (e.g., Namecheap, GoDaddy), create A records:
```
168cap.com → your_droplet_ip
*.168cap.com → your_droplet_ip  (for subdomains)
```

### 2. Verify DNS Propagation
```bash
# Check if DNS is working
dig 168cap.com
dig chat.168cap.com
```

## Directory Structure Setup

### 1. Create Directory Structure
```bash
# Create main directories
cd ~
mkdir -p 168cap-infra/compose
mkdir -p 168cap-infra/nginx/sites-available
mkdir -p 168cap-infra/scripts
mkdir -p 168cap-infra/logs
mkdir -p apps
```

### 2. Clone This Infrastructure Repo
```bash
cd ~
git clone https://github.com/yourusername/168cap-infra.git
```

## NGINX Reverse Proxy Configuration

### 1. Create NGINX Site Configurations
For each domain/subdomain, create a configuration file:

**Main website** (`/etc/nginx/sites-available/168cap.com`):
```nginx
server {
    listen 80;
    server_name 168cap.com www.168cap.com;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**LLM Apps** (e.g., `/etc/nginx/sites-available/chat.168cap.com`):
```nginx
server {
    listen 80;
    server_name chat.168cap.com;
    
    location / {
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 2. Enable Sites
```bash
# Enable sites
ln -s /etc/nginx/sites-available/168cap.com /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/chat.168cap.com /etc/nginx/sites-enabled/

# Test NGINX configuration
nginx -t

# Reload NGINX
systemctl reload nginx
```

## SSL Certificates Setup

### 1. Obtain SSL Certificates
```bash
# Get certificates for all domains
certbot --nginx -d 168cap.com -d www.168cap.com
certbot --nginx -d chat.168cap.com
certbot --nginx -d port.168cap.com

# Set up automatic renewal
systemctl enable certbot.timer
```

## Docker Compose Configuration

### 1. Main Docker Compose File
Create `/compose/docker-compose.yml`:
```yaml
version: '3.9'

services:
  main-website:
    build: ../apps/main-website
    container_name: main_website
    restart: always
    ports:
      - "8000:8000"
    env_file:
      - ../apps/main-website/.env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  chat-app:
    build: ../apps/chat-app
    container_name: chat_app
    restart: always
    ports:
      - "8001:8000"
    env_file:
      - ../apps/chat-app/.env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/docs"]
      interval: 30s
      timeout: 10s
      retries: 3

  port-app:
    build: ../apps/port-app
    container_name: port_app
    restart: always
    ports:
      - "8002:8000"
    env_file:
      - ../apps/port-app/.env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/docs"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 2. Individual App Setup
For each app, ensure it has:

**Dockerfile** (example for FastAPI app):
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Environment file** (`.env`):
```bash
# App-specific environment variables
DATABASE_URL=your_database_url
API_KEY=your_api_key
```

## GitHub Actions CI/CD Setup

### 1. Configure GitHub Secrets
In your GitHub repository, add these secrets:
- `DROPLET_HOST`: Your droplet IP address
- `DROPLET_USER`: SSH username (e.g., `root`)
- `DROPLET_SSH_KEY`: Your private SSH key content

### 2. GitHub Actions Workflow
The included workflow automatically deploys on push to main branch.

## Deployment Commands

### Initial Deployment
```bash
cd ~/168cap-infra/compose
docker-compose up -d --build
```

### Update Apps
```bash
# Full deployment (pulls latest code and rebuilds)
./scripts/deploy.sh

# Restart specific app
./scripts/restart.sh chat-app

# View logs
docker-compose logs -f chat-app
```

## Step-by-Step Guide: Adding New Applications

This section provides detailed actions for adding a new LLM app or website to your infrastructure. Follow these steps in order.

### Prerequisites Checklist
Before starting, ensure:
- [ ] Your app has a working `Dockerfile`
- [ ] App exposes a health check endpoint (`/health` or `/docs`)
- [ ] App runs on port 8000 internally
- [ ] You have a subdomain ready (e.g., `newapp.168cap.com`)
- [ ] DNS A record points to your droplet IP

---

### Step 1: Prepare Your Application Repository

#### 1.1 Create/Update Dockerfile
Ensure your app has a `Dockerfile` in its root directory:

```dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies (if needed)
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port 8000 (standard for all apps)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

#### 1.2 Create Environment File Template
Create `.env.example` in your app repository:
```bash
# App Configuration
APP_NAME=Your New App
DEBUG=false
LOG_LEVEL=info

# API Keys (replace with actual values)
OPENAI_API_KEY=your_openai_key_here
DATABASE_URL=postgresql://user:pass@localhost/dbname

# Other app-specific variables
MAX_TOKENS=4000
RATE_LIMIT=100
```

#### 1.3 Add Health Check Endpoint
Ensure your FastAPI app has a health endpoint:
```python
@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow()}
```

---

### Step 2: Server-Side Setup

#### 2.1 Clone Your App to Server
```bash
# SSH into your droplet
ssh root@your_droplet_ip

# Navigate to apps directory
cd ~/apps

# Clone your new app
git clone https://github.com/yourusername/your-new-app.git

# Verify the structure
ls -la your-new-app/
```

#### 2.2 Create Environment File
```bash
# Copy environment template
cd ~/apps/your-new-app
cp .env.example .env

# Edit with actual values
nano .env
```

#### 2.3 Test App Locally (Optional)
```bash
# Test build locally first
cd ~/apps/your-new-app
docker build -t your-new-app-test .

# Test run (use a temporary port)
docker run -p 9000:8000 --env-file .env your-new-app-test

# Test health endpoint
curl http://localhost:9000/health

# Stop test container
docker stop $(docker ps -q --filter ancestor=your-new-app-test)
```

---

### Step 3: Update Infrastructure Configuration

#### 3.1 Find Next Available Port
```bash
# Check currently used ports in docker-compose.yml
cd ~/168cap-infra/compose
grep -n "ports:" docker-compose.yml

# Use next available port (e.g., if 8002 is last used, use 8003)
```

#### 3.2 Add Service to Docker Compose
Edit `~/168cap-infra/compose/docker-compose.yml`:

```bash
nano ~/168cap-infra/compose/docker-compose.yml
```

Add your new service (replace `your-new-app` and `8003` with your values):

```yaml
  your-new-app:
    build: ../apps/your-new-app
    container_name: your_new_app
    restart: always
    ports:
      - "8003:8000"  # External:Internal port mapping
    env_file:
      - ../apps/your-new-app/.env
    volumes:
      # Add if you need persistent storage
      - your_new_app_data:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      # Add if your app depends on other services
      - some-database
```

If you need volumes, add them at the bottom:
```yaml
volumes:
  your_new_app_data:
```

---

### Step 4: Configure NGINX Reverse Proxy

#### 4.1 Create NGINX Site Configuration
```bash
# Create new site configuration
sudo nano /etc/nginx/sites-available/newapp.168cap.com
```

Add this configuration (replace `newapp.168cap.com` and port `8003`):

```nginx
server {
    listen 80;
    server_name newapp.168cap.com;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Proxy settings
    location / {
        proxy_pass http://localhost:8003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint (optional, for monitoring)
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

#### 4.2 Enable the Site
```bash
# Create symbolic link to enable site
sudo ln -s /etc/nginx/sites-available/newapp.168cap.com /etc/nginx/sites-enabled/

# Test NGINX configuration
sudo nginx -t

# If test passes, reload NGINX
sudo systemctl reload nginx
```

---

### Step 5: DNS and SSL Configuration

#### 5.1 Verify DNS (if not done already)
```bash
# Check if your subdomain resolves to droplet IP
dig newapp.168cap.com

# Should show your droplet IP in A record
```

#### 5.2 Obtain SSL Certificate
```bash
# Get SSL certificate for your new subdomain
sudo certbot --nginx -d newapp.168cap.com

# Verify certificate
sudo certbot certificates
```

---

### Step 6: Deploy and Test

#### 6.1 Deploy Your New App
```bash
# Navigate to compose directory
cd ~/168cap-infra/compose

# Build and start the new service
docker-compose up -d --build your-new-app

# Check if container is running
docker-compose ps

# Check logs for any errors
docker-compose logs -f your-new-app
```

#### 6.2 Test Your Application

**Test internal connectivity:**
```bash
# Test internal port
curl http://localhost:8003/health

# Test through NGINX (HTTP - before SSL)
curl http://newapp.168cap.com/health
```

**Test external connectivity:**
```bash
# Test HTTPS (after SSL setup)
curl https://newapp.168cap.com/health

# Test from external machine
curl -I https://newapp.168cap.com
```

#### 6.3 Monitor Resource Usage
```bash
# Check container resource usage
docker stats

# Check overall system resources
free -h
df -h
```

---

### Step 7: Update Deployment Scripts (Optional)

#### 7.1 Update deploy.sh
If your app needs to be included in automated deployments:

```bash
nano ~/168cap-infra/scripts/deploy.sh
```

Add your app to the deployment script:
```bash
echo "== Pulling latest app code =="
cd ~/apps/port-app && git pull origin main
cd ~/apps/chat-app && git pull origin main
cd ~/apps/your-new-app && git pull origin main  # Add this line
```

#### 7.2 Test Deployment Script
```bash
# Test the updated deployment script
cd ~/168cap-infra/scripts
./deploy.sh
```

---

### Step 8: Update GitHub Actions (if needed)

If you want your new app to be part of the automated CI/CD:

#### 8.1 Update Workflow File
The existing workflow should work automatically since it runs `deploy.sh`, but you can verify:

```bash
cat ~/168cap-infra/.github/workflows/deploy.yml
```

#### 8.2 Test CI/CD
1. Push changes to your infrastructure repo
2. Check GitHub Actions tab for deployment status
3. Verify your app is deployed correctly

---

### Step 9: Final Verification

#### 9.1 Complete System Check
```bash
# Check all containers are running
docker-compose ps

# Check NGINX status
sudo systemctl status nginx

# Check SSL certificates
sudo certbot certificates

# Check disk space
df -h
```

#### 9.2 Functionality Test
1. Visit `https://newapp.168cap.com` in browser
2. Test all major features of your app
3. Check browser developer tools for any errors
4. Test on mobile device (if applicable)

#### 9.3 Monitor for 24 Hours
After deployment, monitor:
- Container logs: `docker-compose logs -f your-new-app`
- NGINX logs: `sudo tail -f /var/log/nginx/access.log`
- System resources: `htop` or `docker stats`

---

### Troubleshooting New App Issues

**Container won't start:**
```bash
# Check build logs
docker-compose logs your-new-app

# Rebuild from scratch
docker-compose build --no-cache your-new-app
docker-compose up -d your-new-app
```

**502 Bad Gateway:**
```bash
# Check if container is running on correct internal port
docker-compose exec your-new-app curl localhost:8000/health

# Check NGINX proxy_pass port matches docker-compose ports
```

**SSL Issues:**
```bash
# Check certificate status
sudo certbot certificates

# Renew if needed
sudo certbot renew --dry-run
```

**Port Conflicts:**
```bash
# Check which ports are in use
netstat -tulpn | grep :80
docker-compose ps
```

This completes the process of adding a new application to your 168cap.com infrastructure.

## Automated App Deployment

To minimize manual work, we've created automation scripts that can deploy new apps with minimal input.

### Option 1: Ultra-Quick Deployment (Recommended)

For fastest deployment when your GitHub repo is ready:

```bash
# Deploy with one command (uses repo name as subdomain)
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/my-chat-app

# Or specify custom health check path
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/my-chat-app /docs
```

This script automatically:
- ✅ Extracts app name from GitHub URL
- ✅ Creates subdomain as `repo-name.168cap.com`
- ✅ Finds next available port
- ✅ Clones/updates your app
- ✅ Creates basic `.env` file
- ✅ Updates Docker Compose
- ✅ Creates NGINX config
- ✅ Deploys container
- ✅ Sets up SSL certificate
- ✅ Tests deployment

**Time: ~2-3 minutes** ⚡

### Option 2: Interactive Deployment (More Control)

For deployments where you want more control or customization:

```bash
~/168cap-infra/scripts/add-new-app.sh
```

This script provides:
- Step-by-step guidance
- Option to customize subdomain
- Detailed error checking
- More configuration options
- Progress feedback

**Time: ~5-7 minutes**

### Option 3: Create New App from Template

To create a new LLM app from scratch:

```bash
# Create FastAPI app template
~/168cap-infra/scripts/create-app-template.sh

# Then deploy it
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/your-new-app
```

Templates include:
- **FastAPI**: Full-featured API with health checks, CORS, error handling
- **Streamlit**: Chat interface with session management
- Pre-configured Dockerfile optimized for 2GB RAM
- Environment variable templates
- Security best practices

### Automation Features

All scripts automatically handle:

**GitHub Integration:**
- Extracts app name from repository URL
- Supports both HTTPS and SSH URLs
- Uses repo name as subdomain (e.g., `my-chat-app.168cap.com`)

**Smart Configuration:**
- Auto-detects next available port
- Creates optimized Docker configurations
- Generates secure NGINX configs with proper headers
- Sets up health checks based on app type

**Zero-Downtime Deployment:**
- Tests container health before proceeding
- Validates NGINX configuration
- Rolls back on failure

**SSL Automation:**
- Automatic Let's Encrypt certificate generation
- Auto-renewal setup
- HTTPS redirect configuration

### Pre-Deployment Checklist

Before running automation scripts, ensure your GitHub repository has:

- [ ] `Dockerfile` in root directory
- [ ] App runs on port 8000 internally
- [ ] Health check endpoint (`/health`, `/docs`, or `/_stcore/health` for Streamlit)
- [ ] `requirements.txt` or equivalent dependencies file
- [ ] `.env.example` template (optional but recommended)

### Example: Complete App Deployment

```bash
# 1. Quick deploy (30 seconds of input, 2-3 minutes total)
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/llm-chat-app

# 2. Configure environment variables (if needed)
nano ~/apps/llm-chat-app/.env

# 3. Restart if env changed
docker-compose restart llm-chat-app

# 4. Test your app
curl https://llm-chat-app.168cap.com/health
# Visit: https://llm-chat-app.168cap.com
```

### Troubleshooting Automation

**Script fails with "port in use":**
```bash
# Check what's using the port
netstat -tulpn | grep :8003
# Or restart all containers
docker-compose restart
```

**SSL certificate fails:**
```bash
# Run manually after deployment
sudo certbot --nginx -d your-app.168cap.com
```

**Container won't start:**
```bash
# Check logs
docker-compose logs your-app-name
# Often missing dependencies in requirements.txt
```

**DNS not resolving:**
```bash
# Check DNS propagation (can take up to 24 hours)
dig your-app.168cap.com
# Use CloudFlare DNS (1.1.1.1) for faster propagation
```

This completes the process of adding a new application to your 168cap.com infrastructure.

## Monitoring and Maintenance

### Check System Resources
```bash
# Check memory usage
free -h

# Check disk space
df -h

# Check running containers
docker ps

# Check container resource usage
docker stats
```

### Logs
```bash
# View all container logs
docker-compose logs

# View specific app logs
docker-compose logs -f chat-app

# View NGINX logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure each service uses unique external ports
2. **SSL issues**: Check certbot logs: `journalctl -u certbot`
3. **Container fails to start**: Check logs: `docker-compose logs service-name`
4. **NGINX errors**: Check config: `nginx -t`
5. **Memory issues**: Monitor with `htop` or `docker stats`

### Health Checks
Each service includes Docker health checks. View status:
```bash
docker-compose ps
```

## Directory Structure
```
~/168cap-infra/
├── compose/
│   └── docker-compose.yml     # Main orchestration file
├── nginx/
│   └── sites-available/       # NGINX configs (copied to /etc/nginx/)
├── scripts/
│   ├── deploy.sh             # Full deployment script
│   └── restart.sh            # Service restart script
├── logs/                     # Optional log storage
└── .github/workflows/        # CI/CD automation

~/apps/
├── main-website/             # Your main 168cap.com site
├── chat-app/                 # LLM chat application
├── port-app/                 # Portfolio or other app
└── [other-apps]/             # Additional applications
```

This setup provides a robust, scalable infrastructure for hosting multiple applications on a single DigitalOcean droplet with proper SSL, reverse proxy, and automated deployment.
