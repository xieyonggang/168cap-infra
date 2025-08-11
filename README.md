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
# Connect to your droplet or use digital ocean web console
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
su yonggangx
sudo curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install NGINX
sudo apt install nginx -y

# Install Certbot for SSL certificates
sudo apt install certbot python3-certbot-nginx -y

# Install Git
sudo apt install git -y

# Restart to apply group changes
logout
# SSH back in
```

### 4. Configure Firewall
```bash
# Enable UFW firewall
su root
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
```


### 1. Setup GitHub Access for Droplet

To allow your droplet (167.99.64.151) to clone repositories from your GitHub account (yonggangxie), you need to configure SSH access to GitHub.

**On your droplet:**

```bash
# SSH into your droplet
ssh yonggangx@167.99.64.151

# Generate SSH key for GitHub access
ssh-keygen -t ed25519 -C "droplet-github-access" -f ~/.ssh/github_rsa

# Display the public key
cat ~/.ssh/github_rsa.pub
```

**On GitHub:**
1. Go to GitHub → Settings → SSH and GPG keys
2. Click "New SSH key"
3. Title: "168cap-droplet-167.99.64.151"
4. Paste the public key content from above
5. Click "Add SSH key"

**Test the connection:**
```bash
# Test GitHub SSH connection
ssh -T -i ~/.ssh/github_rsa git@github.com

# Should show: "Hi yonggangxie! You've successfully authenticated..."
```

**Configure Git on droplet:**
```bash
# Set up Git configuration
git config --global user.name "yonggangxie"
git config --global user.email "yonggang.xie@gmail.com"

# Configure SSH key for GitHub
echo "Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_rsa" >> ~/.ssh/config

chmod 600 ~/.ssh/config
```


## Directory Structure Setup

### Clone This Infrastructure Repo
```bash
su yonggangx
cd ~
git clone git://github.com/xieyonggang/168cap-infra.git
```

## NGINX Reverse Proxy Configuration

### 1. Create NGINX Site Configurations

```
su yonggangx
cd ~/168cap-infra
git pull origin main
sudo cp ~/168cap-infra/nginx/sites-available/* /etc/nginx/sites-available/

```

### 2. Enable Sites
```bash
# Enable sites
su yonggangx
cd ~/168cap-infra
git pull origin main
sudo ln -sf /etc/nginx/sites-available/168cap.com /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/168board.168cap.com /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/168port.168cap.com /etc/nginx/sites-enabled/

# Test NGINX configuration
sudo nginx -t

# Reload NGINX
sudo systemctl reload nginx
```

## SSL Certificates Setup

### 1. Obtain SSL Certificates
```bash
# Get certificates for all domains
sudo certbot --nginx -d 168cap.com -d www.168cap.com
sudo certbot --nginx -d 168board.168cap.com
sudo certbot --nginx -d 168port.168cap.com

# Set up automatic renewal
sudo systemctl enable certbot.timer
```

## GitHub Actions CI/CD Setup

### 1. Configure GitHub Repository Secrets

In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**, then add these secrets:

#### Required Secrets:

**`DROPLET_HOST`**
- **Value**: Your droplet's IP address or domain
- **Example**: `159.203.123.45` or `168cap.com`

**`DROPLET_USER`** 
- **Value**: SSH username for your droplet
- **Example**: `yonggangx` (your created user)

**`DROPLET_SSH_KEY`**
- **Value**: Your private SSH key content (entire file)
- **How to get it**:
```bash
# Copy your private key content
su yonggangx
cat ~/.ssh/github_rsa.pub

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
   - Secret: Paste your entire private key content from `cat ~/.ssh/github_rsa.pub`
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

### 9. Security Best Practices

- **Use dedicated SSH keys** for GitHub Actions (not your personal keys)
- **Limit key permissions** on the droplet to only what's needed
- **Rotate keys regularly** (every 6-12 months)
- **Monitor deployment logs** for any suspicious activity
- **Use specific user** instead of root if possible


#### Test Repository Access

```bash
# Test cloning one of your repositories
cd ~/apps
git clone git@github.com:yonggangxie/168cap.git  # SSH method
# Verify it works
ls -la 168cap/
```

#### Update Automation Scripts

Your automation scripts will now work with your GitHub repositories:

```bash
# Example: Deploy any of your repositories
~/168cap-infra/scripts/quick-deploy.sh git://github.com/yonggangxie/my-llm-chat-app

# The script will automatically clone from your GitHub account
```

#### Troubleshooting GitHub Access

**"Permission denied (publickey)" error:**
```bash
# Test SSH connection to GitHub
ssh -T git@github.com

# Check SSH key is loaded
ssh-add -l

# Add key if needed
ssh-add ~/.ssh/github_rsa
```

#### Common NGINX Permission Issues

**Error: "Permission denied" when testing NGINX config:**
```
nginx: [warn] the "user" directive makes sense only if the master process runs with super-user privileges
nginx: [emerg] open() "/run/nginx.pid" failed (13: Permission denied)
```

**Solution - Always use `sudo` for NGINX commands:**
```bash
# WRONG - Don't run nginx commands as regular user
nginx -t

# CORRECT - Always use sudo for NGINX
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl restart nginx
sudo systemctl status nginx

# When editing NGINX configs, also use sudo
sudo nano /etc/nginx/sites-available/your-site.com
sudo ln -sf /etc/nginx/sites-available/your-site.com /etc/nginx/sites-enabled/
```

#### SSL/Certbot DNSSEC Issues

**Error: DNSSEC validation failure when getting SSL certificates:**
```
Certbot failed to authenticate some domains
DNS problem: DNSSEC: DNSKEY Missing: validation failure
```

**This indicates your domain has DNSSEC enabled but misconfigured. Solutions:**

**Option 1: Disable DNSSEC (Recommended for quick fix)**
```bash
# Check your domain registrar settings and disable DNSSEC
# Common registrars:
# - Namecheap: Domain → Advanced DNS → DNSSEC → Disable
# - GoDaddy: Domain → DNS Management → DNSSEC → Turn Off
# - Cloudflare: SSL/TLS → Edge Certificates → DNSSEC → Disable
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
./scripts/restart.sh 168board

# View logs
docker-compose logs -f 168board
```


## Adding New Apps - Ultra-Quick Deployment

Deploy new apps with a single command:

```bash
# Deploy any GitHub repo as a new app (uses repo name as subdomain)
~/168cap-infra/scripts/quick-deploy.sh git://github.com/yourusername/my-chat-app

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
