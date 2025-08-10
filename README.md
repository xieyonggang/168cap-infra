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

### 1. Generate SSH Key Pair (if you don't have one)

If you don't already have SSH keys set up for your droplet:

```bash
# On your local machine, generate a new SSH key pair
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/168cap_deploy

# This creates two files:
# ~/.ssh/168cap_deploy (private key - for GitHub Secrets)
# ~/.ssh/168cap_deploy.pub (public key - for droplet)
```

### 2. Add Public Key to Your Droplet

```bash
# Copy the public key to your droplet
ssh-copy-id -i ~/.ssh/168cap_deploy.pub root@your_droplet_ip

# Or manually add it:
# 1. Copy the public key content
cat ~/.ssh/168cap_deploy.pub

# 2. SSH into your droplet and add to authorized_keys
ssh root@your_droplet_ip
mkdir -p ~/.ssh
echo "your_public_key_content_here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### 3. Configure GitHub Repository Secrets

In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**, then add these secrets:

#### Required Secrets:

**`DROPLET_HOST`**
- **Value**: Your droplet's IP address or domain
- **Example**: `159.203.123.45` or `168cap.com`

**`DROPLET_USER`** 
- **Value**: SSH username for your droplet
- **Example**: `root` or `yonggangx` (your created user)

**`DROPLET_SSH_KEY`**
- **Value**: Your private SSH key content (entire file)
- **How to get it**:
```bash
# Copy your private key content
cat ~/.ssh/168cap_deploy

# Copy the ENTIRE output including:
# -----BEGIN OPENSSH PRIVATE KEY-----
# ... key content ...
# -----END OPENSSH PRIVATE KEY-----
```

### 4. Step-by-Step Secret Configuration

1. **Navigate to Repository Settings**:
   - Go to your `168cap-infra` repository on GitHub
   - Click **Settings** tab
   - Click **Secrets and variables** in left sidebar
   - Click **Actions**

2. **Add DROPLET_HOST**:
   - Click **New repository secret**
   - Name: `DROPLET_HOST`
   - Secret: `your_droplet_ip` (e.g., `159.203.123.45`)
   - Click **Add secret**

3. **Add DROPLET_USER**:
   - Click **New repository secret**
   - Name: `DROPLET_USER`
   - Secret: `root` (or your SSH username)
   - Click **Add secret**

4. **Add DROPLET_SSH_KEY**:
   - Click **New repository secret**
   - Name: `DROPLET_SSH_KEY`
   - Secret: Paste your entire private key content from `cat ~/.ssh/168cap_deploy`
   - **Important**: Include the header and footer lines
   - Click **Add secret**

### 5. Test SSH Connection

Before relying on GitHub Actions, test the SSH connection:

```bash
# Test SSH connection with your key
ssh -i ~/.ssh/168cap_deploy root@your_droplet_ip

# If successful, you should be able to log in without password
# Test the deployment path exists
ls ~/168cap-infra/scripts/deploy.sh
```

### 6. GitHub Actions Workflow

The included workflow (`.github/workflows/deploy.yml`) automatically:
- Triggers on push to `main` branch
- SSHs into your droplet using the configured secrets
- Runs the deployment script

**Current workflow**:
```yaml
name: Deploy to Droplet

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: SSH into Droplet and Deploy
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.DROPLET_HOST }}
          username: ${{ secrets.DROPLET_USER }}
          key: ${{ secrets.DROPLET_SSH_KEY }}
          script: |
            cd ~/168cap-infra/scripts
            ./deploy.sh
```

### 7. Verify GitHub Actions Setup

1. **Check Secrets**: Go to repository Settings → Secrets and variables → Actions
   - You should see 3 secrets: `DROPLET_HOST`, `DROPLET_USER`, `DROPLET_SSH_KEY`

2. **Test Deployment**: Make a small change and push to main branch
   ```bash
   # Make a test change
   echo "# Test" >> README.md
   git add README.md
   git commit -m "Test GitHub Actions deployment"
   git push origin main
   ```

3. **Monitor Deployment**: 
   - Go to **Actions** tab in your repository
   - Watch the workflow execution
   - Check for any errors in the logs

### 8. Troubleshooting GitHub Actions

**"Permission denied (publickey)" error**:
```bash
# Verify your private key is correct
ssh -i ~/.ssh/168cap_deploy root@your_droplet_ip

# Check if public key is in authorized_keys on droplet
cat ~/.ssh/authorized_keys
```

**"Host key verification failed"**:
- The SSH action might fail on first run due to host key verification
- Add this to your workflow for first-time setup:
```yaml
- name: SSH into Droplet and Deploy
  uses: appleboy/ssh-action@v1.0.0
  with:
    host: ${{ secrets.DROPLET_HOST }}
    username: ${{ secrets.DROPLET_USER }}
    key: ${{ secrets.DROPLET_SSH_KEY }}
    script_stop: true
    script: |
      cd ~/168cap-infra/scripts
      ./deploy.sh
```

**"deploy.sh not found"**:
```bash
# SSH into droplet and verify paths
ssh root@your_droplet_ip
ls ~/168cap-infra/scripts/deploy.sh
chmod +x ~/168cap-infra/scripts/deploy.sh
```

### 9. Security Best Practices

- **Use dedicated SSH keys** for GitHub Actions (not your personal keys)
- **Limit key permissions** on the droplet to only what's needed
- **Rotate keys regularly** (every 6-12 months)
- **Monitor deployment logs** for any suspicious activity
- **Use specific user** instead of root if possible

### 10. Optional: Non-Root Deployment User

For better security, create a dedicated deployment user:

```bash
# On your droplet, create deploy user
sudo adduser deploy
sudo usermod -aG docker deploy
sudo usermod -aG sudo deploy

# Set up SSH key for deploy user
sudo su - deploy
mkdir -p ~/.ssh
# Add your public key to ~/.ssh/authorized_keys

# Update GitHub secret DROPLET_USER to "deploy"
```

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


## Adding New Apps - Ultra-Quick Deployment

Deploy new apps with a single command:

```bash
# Deploy any GitHub repo as a new app (uses repo name as subdomain)
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/my-chat-app

# Or specify custom health check path
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/my-chat-app /docs
```

**What it does automatically:**
- ✅ Extracts app name from GitHub URL → Creates `my-chat-app.168cap.com`
- ✅ Finds next available port
- ✅ Clones/updates your app
- ✅ Creates `.env` file from template
- ✅ Updates Docker Compose config
- ✅ Creates NGINX reverse proxy
- ✅ Deploys container
- ✅ Sets up SSL certificate
- ✅ Tests everything works

**Time: ~2-3 minutes total** ⚡

### Requirements for Your App Repository

Before deployment, ensure your GitHub repo has:
- [ ] `Dockerfile` in root directory
- [ ] App runs on port 8000 internally
- [ ] Health check endpoint (`/health`, `/docs`, or `/_stcore/health` for Streamlit)
- [ ] `requirements.txt` or equivalent dependencies file

### Complete Example

```bash
# 1. Deploy your app
~/168cap-infra/scripts/quick-deploy.sh https://github.com/yourusername/llm-chat-app

# 2. Configure environment variables (if needed)
nano ~/apps/llm-chat-app/.env
docker-compose restart llm-chat-app

# 3. Your app is live at: https://llm-chat-app.168cap.com
```

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
