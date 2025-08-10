# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an infrastructure repository for deploying multiple FastAPI-based applications (`port.168cap.com`, `chat.168cap.com`) on a single DigitalOcean droplet using Docker Compose and NGINX reverse proxy.

## Key Commands

### Deployment
- **Full deployment**: `./scripts/deploy.sh` - Pulls latest code for all apps, rebuilds containers, and restarts services
- **Restart specific app**: `./scripts/restart.sh <service-name>` (e.g., `./scripts/restart.sh port-app`)
- **Restart all services**: `./scripts/restart.sh` (no arguments)

### Docker Operations
- **View services**: `docker-compose ps` (run from `/compose` directory)
- **View logs**: `docker-compose logs <service-name>`
- **Rebuild specific service**: `docker-compose up -d --build <service-name>`

## Architecture

### Multi-App Infrastructure Pattern
- **Central orchestration**: Docker Compose file at `/compose/docker-compose.yml` manages all applications
- **Reverse proxy**: NGINX configs in `/nginx/sites-available/` route traffic to containerized apps
- **Port mapping**: Each app runs on internal port 8000, mapped to external ports (8010, 8011, etc.)
- **App isolation**: Individual apps are stored in `/apps/<app-name>/` on the server (not in this repo)

### Service Structure
Each service follows this pattern:
- Built from `../apps/<app-name>` directory
- Exposed on unique external port (8010+)
- Uses individual `.env` files
- Health checks via `/docs` endpoint
- Auto-restart policy enabled

### Deployment Flow
1. GitHub Actions triggers on main branch push
2. SSH into droplet using secrets (DROPLET_HOST, DROPLET_USER, DROPLET_SSH_KEY)
3. Execute `deploy.sh` script which:
   - Pulls latest code for all apps from their respective repos
   - Rebuilds Docker containers
   - Restarts services with zero-downtime deployment

## Adding New Applications

To add a new FastAPI app:
1. Clone app repository to `/apps/<app-name>` on server
2. Add service definition to `docker-compose.yml` with unique port mapping
3. Create NGINX config file in `/nginx/sites-available/<domain>`
4. Configure SSL with certbot for the domain
5. Add health check endpoint (`/docs` is standard)

## Important Paths
- `/compose/docker-compose.yml`: Main service orchestration
- `/scripts/deploy.sh`: Full deployment automation
- `/scripts/restart.sh`: Service restart utility  
- `/nginx/sites-available/`: Domain-specific reverse proxy configs
- `/.github/workflows/deploy.yml`: CI/CD automation

## Environment Requirements
- Server must have Docker, NGINX, and Certbot installed
- Apps must be cloned to `/apps/` directory structure on server
- GitHub secrets must be configured for automated deployment
- Each app requires its own `.env` file for configuration