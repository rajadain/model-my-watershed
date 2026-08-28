# Model My Watershed: Docker & ECS Migration Specification

**Version:** 1.0  
**Date:** January 24, 2026  
**Purpose:** Comprehensive specification for migrating MMW infrastructure from Vagrant/VirtualBox to Docker (development) and from EC2/CloudFormation to ECS/Terraform (production).

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current System Architecture](#2-current-system-architecture)
3. [Target Architecture](#3-target-architecture)
4. [Service Inventory](#4-service-inventory)
5. [Phase 1: Docker Development Environment](#5-phase-1-docker-development-environment)
6. [Phase 2: Terraform ECS Production Deployment](#6-phase-2-terraform-ecs-production-deployment)
7. [Data Migration Considerations](#7-data-migration-considerations)
8. [Testing Strategy](#8-testing-strategy)

---

## 1. Executive Summary

### 1.1 Project Overview

Model My Watershed (MMW) is a web-based watershed modeling application consisting of:

- **Frontend**: JavaScript (Backbone + Marionette) with SCSS
- **Backend API**: Django with Django REST Framework
- **Task Queue**: Celery with Redis broker
- **Tile Server**: Windshaft (Node.js) for map tiles
- **Geoprocessing**: Custom GeoTrellis service (Java JAR)
- **Watershed Delineation**: RWD (already containerized)
- **Database**: PostgreSQL 17 with PostGIS 3
- **Cache**: Redis 6.0

### 1.2 Migration Goals

| Current State | Target State |
|---------------|--------------|
| 4 Vagrant VirtualBox VMs | Docker Compose (development) |
| Packer AMIs + CloudFormation | Terraform + ECS Fargate (production) |
| Ansible provisioning | Dockerfiles + container orchestration |
| EC2 Auto Scaling Groups | ECS Services with auto-scaling |
| Classic ELB | Application Load Balancer |
| Nginx reverse proxy | Direct Gunicorn access (dev), ALB routing (prod) |
| Static files via Nginx | Django/WhiteNoise (dev), S3+CloudFront (prod) |

### 1.3 Migration Phases

1. **Phase 1**: Docker development environment (test locally first)
2. **Phase 2**: Terraform ECS production deployment (after Phase 1 validated)

---

## 2. Current System Architecture

### 2.1 Development Environment (Vagrant)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HOST MACHINE                                       │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  services   │  │    app      │  │   worker    │  │   tiler     │        │
│  │  VM         │  │   VM        │  │   VM        │  │   VM        │        │
│  │             │  │             │  │             │  │             │        │
│  │ PostgreSQL  │  │ Nginx       │  │ Celery      │  │ Nginx       │        │
│  │ :5432       │  │ :80→:8000   │  │ Workers     │  │ :80→:4000   │        │
│  │             │  │             │  │             │  │             │        │
│  │ Redis       │  │ Gunicorn    │  │ Geoprocess  │  │ Windshaft   │        │
│  │ :6379       │  │ :8000       │  │ :8090       │  │ :4000       │        │
│  │             │  │             │  │             │  │             │        │
│  │             │  │             │  │ RWD Docker  │  │             │        │
│  │             │  │             │  │ :5000       │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│   33.33.34.30      33.33.34.10      33.33.34.20      33.33.34.35           │
│   Port: 5432       Port: 8000       Port: 8090       Port: 4000            │
│   Port: 6379       Port: 35729      Port: 2375                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Production Environment (AWS)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS VPC (10.0.0.0/16)                          │
│                                                                             │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐        │
│  │       Public Subnets        │    │      Private Subnets        │        │
│  │                             │    │                             │        │
│  │  ┌─────────────────────┐    │    │  ┌─────────────────────┐   │        │
│  │  │   Bastion Host      │    │    │  │   App Server ASG    │   │        │
│  │  │   (t2.medium)       │    │    │  │   (t2.small)        │   │        │
│  │  └─────────────────────┘    │    │  └─────────────────────┘   │        │
│  │                             │    │                             │        │
│  │  ┌─────────────────────┐    │    │  ┌─────────────────────┐   │        │
│  │  │   NAT Instances     │    │    │  │  Worker Server ASG  │   │        │
│  │  │   (t2.micro)        │    │    │  │   (t2.micro)        │   │        │
│  │  └─────────────────────┘    │    │  │   + 512GB EBS       │   │        │
│  │                             │    │  └─────────────────────┘   │        │
│  │  ┌─────────────────────┐    │    │                             │        │
│  │  │   App ELB (80/443)  │    │    │  ┌─────────────────────┐   │        │
│  │  │   Tile ELB (80/443) │    │    │  │  Tile Server ASG    │   │        │
│  │  └─────────────────────┘    │    │  │   (t2.micro)        │   │        │
│  │                             │    │  └─────────────────────┘   │        │
│  └─────────────────────────────┘    └─────────────────────────────┘        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                         Data Plane                               │       │
│  │   ┌─────────────────┐              ┌─────────────────┐          │       │
│  │   │      RDS        │              │   ElastiCache   │          │       │
│  │   │   PostgreSQL    │              │     Redis       │          │       │
│  │   │   (db.t3.micro) │              │ (cache.m1.small)│          │       │
│  │   └─────────────────┘              └─────────────────┘          │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │   CloudFront → S3 (tile-cache bucket)                            │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Key File Locations

| Component | Source Location | Config Location |
|-----------|-----------------|-----------------|
| Django App | `src/mmw/` | `src/mmw/mmw/settings/` |
| Tiler | `src/tiler/` | `src/tiler/server.js` |
| Ansible Roles | `deployment/ansible/roles/` | `deployment/ansible/group_vars/` |
| CloudFormation | `deployment/cfn/` | `deployment/default.yml.example` |
| Packer | `deployment/packer/mmw.json` | - |
| Vagrantfile | `Vagrantfile` | - |
| Development Scripts | `scripts/` | - |
| Frontend Bundle | `src/mmw/bundle.sh` | - |

### 2.4 Current Development Scripts

The project uses shell scripts in `scripts/` that wrap `vagrant ssh` commands. These must be replaced with Docker equivalents.

| Script | Purpose | Command Pattern |
|--------|---------|-----------------|
| `scripts/manage.sh` | Run Django management commands | `vagrant ssh app -c "cd /opt/app && envdir /etc/mmw.d/env ./manage.py $ARGS"` |
| `scripts/bundle.sh` | Bundle JS/CSS static assets | `vagrant ssh app -c "cd /opt/app && envdir /etc/mmw.d/env ./bundle.sh $ARGS"` |
| `scripts/yarn.sh` | Run yarn commands | `vagrant ssh app -c "cd /opt/app && envdir /etc/mmw.d/env yarn $ARGS"` |
| `scripts/test.sh` | Run full test suite | Runs flake8, Django tests, and JS tests via testem |
| `scripts/testem.sh` | Run JS tests interactively | `vagrant ssh app -c "... testem -f /opt/app/testem.json $*"` |
| `scripts/check.sh` | Run flake8 linting | `vagrant ssh app -c "flake8 /opt/app/apps --exclude migrations"` |
| `scripts/debugserver.sh` | Run Django dev server | Stops service, runs gunicorn interactively |
| `scripts/debugcelery.sh` | Run Celery worker interactively | Stops service, runs celery with debug logging |
| `scripts/debugtiler.sh` | Run tiler with watch mode | Stops service, runs `npm run watch` |
| `scripts/toggle_feature.sh` | Toggle feature flags | Modifies `/etc/mmw.d/env/MMW_ENABLED_FEATURES` |
| `scripts/vagrant-up.sh` | Start all VMs with retry logic | Provisions services, app, worker in order |

#### Frontend Build System (`src/mmw/bundle.sh`)

The frontend build script supports several modes:

```bash
./bundle.sh [OPTIONS]
  --watch    # Use watchify for live rebuilding
  --debug    # Generate source maps
  --minify   # Minify bundles (slow, no source maps)
  --tests    # Generate test bundles
  --list     # List browserify dependencies
  --vendor   # Generate vendor bundle and copy assets
```

Key operations:
- **Browserify/Watchify**: Bundles `js/src/main.js` → static JS
- **Node-sass**: Compiles `sass/main.scss` → static CSS
- **Asset copying**: Copies images, fonts, resources to static directory

#### Database Setup (`scripts/aws/setupdb.sh`)

Used to load geospatial data into PostgreSQL:

```bash
./setupdb.sh [OPTIONS]
  -b  # Load boundary data (counties, HUCs, districts)
  -s  # Load stream data (NHD flowlines)
  -S  # Load Hi-Res stream data (large)
  -t  # Load TDX Hydro streams (EXTREMELY LARGE)
  -d  # Load DRB stream data
  -m  # Load mapshed data
  -p  # Load DEP data
  -c  # Load NHDPlus catchment data
  -q  # Load water quality data
  -X  # Purge S3 tile cache
```

Data is downloaded from `https://s3.amazonaws.com/data.mmw.azavea.com/` and loaded via psql.

#### Test Suite Components

1. **Python/Django tests**: `python manage.py test --noinput --exclude-tag=mapshed`
2. **Flake8 linting**: `flake8 /opt/app/apps --exclude migrations`
3. **JavaScript tests**: Testem with xvfb for headless browser testing
4. **Skip JS tests**: Set `MMW_SKIP_JS_TESTS=1` environment variable

---

## 3. Target Architecture

### 3.1 Docker Development Environment

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HOST MACHINE                                       │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Docker Compose Network                           │   │
│  │                                                                       │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐         │   │
│  │  │ postgres  │  │   redis   │  │    app    │  │  celery   │         │   │
│  │  │ :5432     │  │  :6379    │  │  :8000    │  │ (worker)  │         │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘         │   │
│  │                                                                       │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                         │   │
│  │  │  tiler    │  │   geop    │  │    rwd    │                         │   │
│  │  │  :4000    │  │  :8090    │  │  :5000    │                         │   │
│  │  └───────────┘  └───────────┘  └───────────┘                         │   │
│  │                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Volumes:                                                                   │
│  - ./src/mmw → /opt/app (app, celery)                                      │
│  - ./src/tiler → /opt/tiler (tiler)                                        │
│  - postgres-data → /var/lib/postgresql/data                                 │
│  - rwd-data → /opt/rwd-data                                                 │
│                                                                             │
│  Note: No nginx needed - Django serves static files directly in dev mode.  │
│  Gunicorn binds to 0.0.0.0:8000 for direct access.                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 ECS Production Environment

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS VPC                                         │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     ECS Cluster (Fargate)                            │   │
│  │                                                                       │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐            │   │
│  │  │  App Service  │  │ Worker Service│  │ Tiler Service │            │   │
│  │  │  (Fargate)    │  │  (Fargate)    │  │  (Fargate)    │            │   │
│  │  │               │  │               │  │               │            │   │
│  │  │ ┌───────────┐ │  │ ┌───────────┐ │  │ ┌───────────┐ │            │   │
│  │  │ │ gunicorn  │ │  │ │  celery   │ │  │ │ windshaft │ │            │   │
│  │  │ │  :8000    │ │  │ │   geop    │ │  │ │   :4000   │ │            │   │
│  │  │ └───────────┘ │  │ │   rwd     │ │  │ └───────────┘ │            │   │
│  │  └───────────────┘  │ └───────────┘ │  └───────────────┘            │   │
│  │         │           └───────────────┘         │                      │   │
│  │         │                  │                  │                      │   │
│  └─────────┼──────────────────┼──────────────────┼──────────────────────┘   │
│            │                  │                  │                          │
│  ┌─────────▼──────────────────┼──────────────────▼──────────────────────┐   │
│  │                Application Load Balancer                              │   │
│  │   HTTPS termination, health checks, path-based routing               │   │
│  │   /* → app:8000       /tiles/* → tiler:4000                          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              CloudFront + S3                                         │   │
│  │   /static/* → S3 bucket    /media/* → S3 bucket    tile-cache → S3  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │   RDS PostgreSQL          ElastiCache Redis                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │   ECR Repositories: mmw-app, mmw-tiler, mmw-worker, mmw-geop        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Note: No nginx needed - ALB handles HTTPS, routing, and health checks.    │
│  S3 + CloudFront serves static/media files with caching.                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Service Inventory

### 4.1 Services to Containerize

| Service | Base Image | Port | Health Check | Notes |
|---------|------------|------|--------------|-------|
| **app** | python:3.10-slim | 8000 | `/health-check/` | Django + Gunicorn |
| **celery** | python:3.10-slim | - | Celery inspect | Same image as app |
| **tiler** | node:10.16.0 | 4000 | `/health-check` | Requires Mapnik |
| **geop** | eclipse-temurin:8 | 8090 | `/health-check` | Java JAR download |
| **rwd** | quay.io/wikiwatershed/rwd:2.0.0 | 5000 | HTTP check | Already containerized |
| **postgres** | postgis/postgis:17-3.5 | 5432 | `pg_isready` | Dev only |
| **redis** | redis:6.0-alpine | 6379 | `redis-cli ping` | Dev only |

**Note:** Nginx is intentionally omitted. In development, Django serves static files directly
(via `DEBUG=True` or WhiteNoise). In production, ALB handles routing/HTTPS and S3+CloudFront
serves static/media files.

### 4.2 Why No Nginx?

The current Vagrant setup uses nginx as a reverse proxy in front of Gunicorn (Django) and
Windshaft (Tiler). Analysis of the nginx configuration reveals these responsibilities:

| Nginx Function | Docker Dev Replacement | ECS Prod Replacement |
|----------------|----------------------|----------------------|
| Serve `/static/*` | Django (DEBUG=True) or WhiteNoise | S3 + CloudFront |
| Serve `/media/*` | Django directly | S3 + CloudFront |
| HTTPS termination | Not needed locally | ALB handles SSL |
| HTTP → HTTPS redirect | Not needed locally | ALB listener rule |
| Proxy to Gunicorn | Direct access to Gunicorn | ALB → ECS target group |
| Health check routing | Direct health check | ALB health checks |
| Caching headers | Django middleware or WhiteNoise | S3/CloudFront metadata |
| Client body size limit | Gunicorn/Django settings | ALB settings |
| Real IP / X-Forwarded-For | Not needed locally | ALB adds automatically |

**Benefits of removing nginx:**
- Fewer containers to manage (simpler architecture)
- Faster startup times
- Direct debugging of Django (no proxy layer)
- Closer parity between dev and prod routing logic
- ALB is more robust than nginx for load balancing
- S3/CloudFront is more efficient for static file serving

### 4.2 Environment Variables

#### Common Variables (All Services)

```bash
# Database
MMW_DB_NAME=mmw
MMW_DB_USER=mmw
MMW_DB_PASSWORD=mmw
MMW_DB_HOST=postgres        # 'postgres' in Docker, RDS endpoint in prod
MMW_DB_PORT=5432

# Cache
MMW_CACHE_HOST=redis        # 'redis' in Docker, ElastiCache endpoint in prod
MMW_CACHE_PORT=6379

# Stack
MMW_STACK_COLOR=Black       # Blue/Green in production
MMW_STACK_TYPE=Development  # Staging/Production
AWS_REGION=us-east-1
```

#### App-Specific Variables

```bash
DJANGO_SETTINGS_MODULE=mmw.settings.development  # or mmw.settings.production
DJANGO_SECRET_KEY=<secret>
DJANGO_STATIC_ROOT=/var/www/mmw/static
DJANGO_MEDIA_ROOT=/var/www/mmw/media
DJANGO_POSTGIS_VERSION=3.5.0

# External Services
MMW_TILER_HOST=tiler:4000   # or tiles.modelmywatershed.org in prod
MMW_GEOPROCESSING_HOST=geop
MMW_GEOPROCESSING_PORT=8090
MMW_GEOPROCESSING_VERSION=6.1.0
MMW_GEOPROCESSING_TIMEOUT=120

# OAuth (if needed)
MMW_ITSI_CLIENT_ID=<client_id>
MMW_ITSI_SECRET_KEY=<secret>
MMW_HYDROSHARE_CLIENT_ID=<client_id>
MMW_HYDROSHARE_SECRET_KEY=<secret>
```

#### Celery-Specific Variables

```bash
CELERY_APP=mmw.celery:app
CELERYD_LOG_LEVEL=DEBUG
CELERYD_OPTS=--time-limit=300 --concurrency=2

# RWD
RWD_HOST=rwd
RWD_PORT=5000
```

#### Tiler-Specific Variables

```bash
MMW_TILECACHE_BUCKET=       # S3 bucket for tile caching (prod only)
MMW_TITILER_HOST=           # TiTiler service URL
MMW_TITILER_LAYER_MAP=      # Layer mappings for TiTiler
ROLLBAR_ACCESS_TOKEN=       # Error tracking (prod only)
```

### 4.3 Volume Mappings

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `./src/mmw` | `/opt/app` | Django source (dev) |
| `./src/tiler` | `/opt/tiler` | Tiler source (dev) |
| `postgres-data` | `/var/lib/postgresql/data` | Database persistence |
| `rwd-data` | `/opt/rwd-data` | RWD watershed data |
| `static-files` | `/var/www/mmw/static` | Collected static files |
| `media-files` | `/var/www/mmw/media` | User uploads |

### 4.4 Port Mappings

| Host Port | Container | Service Port | Description |
|-----------|-----------|--------------|-------------|
| 8000 | app | 8000 | Django/Gunicorn (serves static in dev) |
| 4000 | tiler | 4000 | Tile server |
| 5432 | postgres | 5432 | Database |
| 6379 | redis | 6379 | Cache/broker |
| 8090 | geop | 8090 | Geoprocessing API |
| 5000 | rwd | 5000 | Watershed delineation |
| 35729 | app | 35729 | Livereload (dev) |

---

## 5. Phase 1: Docker Development Environment

### 5.1 Overview

Create a complete Docker-based development environment that replaces the 4 Vagrant VMs while maintaining the same developer experience.

### 5.2 Directory Structure to Create

```
/
├── docker/
│   ├── app/
│   │   └── Dockerfile
│   ├── tiler/
│   │   └── Dockerfile
│   ├── geop/
│   │   └── Dockerfile
│   └── postgres/
│       └── init.sql              # PostGIS + pg_trgm setup
├── docker-compose.yml
├── docker-compose.override.yml      # Development overrides
├── .env.example                      # Environment template
└── scripts/
    └── docker/
        ├── start.sh
        ├── stop.sh
        ├── logs.sh
        ├── shell.sh
        ├── manage.sh                 # Django management
        ├── bundle.sh                 # Frontend build
        ├── test.sh
        └── migrate.sh
```

### 5.3 Step-by-Step Implementation Tasks

#### Task 1: Create Base Dockerfiles

**1.1 App Dockerfile (`docker/app/Dockerfile`)**

Create a Dockerfile for the Django application that:

- Uses `python:3.10-slim` as base
- Installs system dependencies: `libpq-dev`, `gdal-bin`, `libgdal-dev`, `binutils`, `libproj-dev`, `python3-dev`, `gcc`, `g++`
- Installs `xvfb` for headless browser testing (testem)
- Sets working directory to `/opt/app`
- Installs Python dependencies from `src/mmw/requirements/development.txt` (or `production.txt` for prod build)
- Installs Node.js 12.11.1 and Yarn for frontend build
- Runs `yarn install` and `yarn bundle` for frontend assets
- Collects static files with `python manage.py collectstatic`
- Exposes port 8000
- Default command: `gunicorn --bind 0.0.0.0:8000 --workers 2 mmw.wsgi`

Key packages to install from Ansible roles:
```
# From model-my-watershed.app
llvmlite numba

# From azavea.yarn (frontend build)
yarn

# Geospatial
gdal-bin libgdal-dev libproj-dev binutils

# For testem/browser testing
xvfb chromium
```

**Frontend Build Tools Required:**

The `src/mmw/bundle.sh` script requires these Node.js tools:
- `browserify` / `watchify` - JS module bundling
- `node-sass` - SCSS compilation
- `nunjucksify` - Template transform for browserify
- `minifyify` - JS minification (production)
- `testem` - JS test runner

The Dockerfile should ensure the bundle script can run with all options:
```bash
./bundle.sh --vendor  # Copy vendor assets (images, fonts, resources)
./bundle.sh           # Build main bundles
./bundle.sh --watch   # Development mode with live reload
./bundle.sh --debug   # Source maps enabled
./bundle.sh --minify  # Production minification
./bundle.sh --tests   # Build test bundles
```

**Static File Serving (No Nginx Required):**

In development, Django serves static files directly when `DEBUG=True`. For production,
add WhiteNoise middleware for efficient static file serving, or serve from S3/CloudFront.

Add to Django settings for development:
```python
# settings/docker.py or settings/development.py
DEBUG = True  # Django serves /static/ automatically

# Or use WhiteNoise for both dev and prod:
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',  # Add after security
    # ... rest of middleware
]
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
```

**1.2 Tiler Dockerfile (`docker/tiler/Dockerfile`)**

Create a Dockerfile for the Windshaft tiler that:

- Uses `node:10.16.0` as base (Windshaft requires older Node)
- Installs system dependencies for Mapnik:
  - `libcairo2-dev`, `libpango1.0-dev`, `libjpeg8-dev`, `libgif-dev`
  - `libmapnik3.1`, `libmapnik-dev`, `mapnik-utils`
- Sets working directory to `/opt/tiler`
- Copies `package.json` and runs `npm install`
- Copies source code
- Exposes port 4000
- Default command: `node server.js`

**1.3 Geoprocessing Dockerfile (`docker/geop/Dockerfile`)**

Create a Dockerfile for the GeoTrellis service that:

- Uses `eclipse-temurin:8-jre` as base
- Sets `GEOP_VERSION=6.1.0` as ARG
- Downloads JAR from GitHub releases:
  `https://github.com/WikiWatershed/mmw-geoprocessing/releases/download/${GEOP_VERSION}/api-assembly-${GEOP_VERSION}.jar`
- Sets working directory to `/opt/geoprocessing`
- Exposes port 8090
- Default command: `java -jar mmw-geoprocessing-${GEOP_VERSION}.jar`

**Note:** No Nginx Dockerfile is needed. See Section 4.1 for rationale.

#### Task 2: Create Docker Compose Configuration

**2.1 Main docker-compose.yml**

Create the main compose file with these services:

```yaml
services:
  postgres:
    image: postgis/postgis:17-3.5
    environment:
      POSTGRES_DB: mmw
      POSTGRES_USER: mmw
      POSTGRES_PASSWORD: mmw
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mmw"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:6.0-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    build:
      context: .
      dockerfile: docker/app/Dockerfile
    environment:
      DJANGO_SETTINGS_MODULE: mmw.settings.docker
      DJANGO_SECRET_KEY: development-secret-key
      DJANGO_STATIC_ROOT: /var/www/mmw/static/
      DJANGO_MEDIA_ROOT: /var/www/mmw/media/
      MMW_DB_HOST: postgres
      MMW_DB_NAME: mmw
      MMW_DB_USER: mmw
      MMW_DB_PASSWORD: mmw
      MMW_CACHE_HOST: redis
      MMW_CACHE_PORT: 6379
      MMW_TILER_HOST: tiler:4000
      MMW_GEOPROCESSING_HOST: geop
      MMW_GEOPROCESSING_PORT: 8090
      RWD_HOST: rwd
      RWD_PORT: 5000
    volumes:
      - ./src/mmw:/opt/app
      - static-files:/var/www/mmw/static
      - media-files:/var/www/mmw/media
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "8000:8000"
      - "35729:35729"  # Livereload
    # In dev mode, Django serves static files directly (DEBUG=True)

  celery:
    build:
      context: .
      dockerfile: docker/app/Dockerfile
    command: celery -A mmw.celery:app worker -l debug -c 2
    environment:
      # Same as app, plus:
      CELERY_APP: mmw.celery:app
      CELERYD_LOG_LEVEL: DEBUG
    volumes:
      - ./src/mmw:/opt/app
      - media-files:/var/www/mmw/media
    depends_on:
      - app
      - redis
      - geop
      - rwd

  tiler:
    build:
      context: .
      dockerfile: docker/tiler/Dockerfile
    environment:
      MMW_DB_HOST: postgres
      MMW_DB_NAME: mmw
      MMW_DB_USER: mmw
      MMW_DB_PASSWORD: mmw
      MMW_DB_PORT: 5432
      MMW_CACHE_HOST: redis
      MMW_CACHE_PORT: 6379
    volumes:
      - ./src/tiler:/opt/tiler
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "4000:4000"

  geop:
    build:
      context: .
      dockerfile: docker/geop/Dockerfile
    environment:
      AWS_REGION: us-east-1
    ports:
      - "8090:8090"

  rwd:
    image: quay.io/wikiwatershed/rwd:2.0.0
    volumes:
      - ${RWD_DATA:-./data/rwd}:/opt/rwd-data:ro
    ports:
      - "5000:5000"

volumes:
  postgres-data:
  static-files:
  media-files:

networks:
  default:
    name: mmw-network
```

**Note:** No nginx service is needed. The `app` container serves the application
directly on port 8000, and Django handles static files in development mode.
The `tiler` service is accessed directly on port 4000.

**2.2 Development override (`docker-compose.override.yml`)**

Add development-specific configuration:

- Enable hot-reloading for app (use `--reload` flag for gunicorn)
- Enable `npm run watch` for tiler
- Mount source code as volumes
- Add livereload service
- Enable debug logging

#### Task 3: Create Helper Scripts

Create Docker equivalents of the existing Vagrant scripts. These should be drop-in replacements that developers can use with minimal workflow changes.

**3.1 scripts/docker/start.sh** (replaces `vagrant up`)
```bash
#!/bin/bash
# Start all services
set -e
docker compose up -d
echo "Services started. View logs with: docker compose logs -f"
echo "App available at: http://localhost:8000"
```

**3.2 scripts/docker/stop.sh** (replaces `vagrant halt`)
```bash
#!/bin/bash
# Stop all services
docker compose down
```

**3.3 scripts/docker/manage.sh** (replaces `scripts/manage.sh`)
```bash
#!/bin/bash
# Run Django management commands
# Usage: ./scripts/docker/manage.sh migrate
#        ./scripts/docker/manage.sh shell
#        ./scripts/docker/manage.sh runserver 0.0.0.0:8000
set -e
ARGS=${*:-"help"}

# Sane defaults for runserver (match existing behavior)
if [[ $# -eq 1 ]] && [[ $1 == runserver ]]; then
    ARGS="runserver 0.0.0.0:8000"
fi

docker compose exec app python manage.py $ARGS
```

**3.4 scripts/docker/bundle.sh** (replaces `scripts/bundle.sh`)
```bash
#!/bin/bash
# Bundle JS and CSS static assets
# Usage: ./scripts/docker/bundle.sh
#        ./scripts/docker/bundle.sh --watch
#        ./scripts/docker/bundle.sh --debug
#        ./scripts/docker/bundle.sh --vendor
set -e
docker compose exec app ./bundle.sh "$@"
```

**3.5 scripts/docker/yarn.sh** (replaces `scripts/yarn.sh`)
```bash
#!/bin/bash
# Run yarn commands
# Usage: ./scripts/docker/yarn.sh install
#        ./scripts/docker/yarn.sh add <package>
set -e
docker compose exec app yarn "$@"
```

**3.6 scripts/docker/test.sh** (replaces `scripts/test.sh`)
```bash
#!/bin/bash
# Run the full test suite
set -e
set -x

# Run flake8 against Django codebase
docker compose exec app flake8 /opt/app/apps --exclude migrations || echo "flake8 check failed"

# Run Django tests
docker compose exec app python manage.py test --noinput --exclude-tag=mapshed

# Run JS unit tests (unless skipped)
if [[ -z "${MMW_SKIP_JS_TESTS}" ]]; then
    docker compose exec app xvfb-run ./node_modules/.bin/testem -f testem.json ci "$@"
else
    echo "SKIPPING JS TESTS"
fi
```

**3.7 scripts/docker/testem.sh** (replaces `scripts/testem.sh`)
```bash
#!/bin/bash
# Run JS tests interactively
set -e
docker compose exec app ./node_modules/.bin/testem -f testem.json "$@"
```

**3.8 scripts/docker/check.sh** (replaces `scripts/check.sh`)
```bash
#!/bin/bash
# Run flake8 linting
set -e
docker compose exec app flake8 /opt/app/apps --exclude migrations
```

**3.9 scripts/docker/shell.sh** (new convenience script)
```bash
#!/bin/bash
# Get a shell in a container
# Usage: ./scripts/docker/shell.sh        # app container (default)
#        ./scripts/docker/shell.sh tiler  # tiler container
SERVICE=${1:-app}
docker compose exec $SERVICE /bin/bash
```

**3.10 scripts/docker/debugserver.sh** (replaces `scripts/debugserver.sh`)
```bash
#!/bin/bash
# Run Django dev server with auto-reload (foreground)
set -e
docker compose stop app
docker compose run --rm --service-ports app \
    gunicorn --reload --bind 0.0.0.0:8000 --workers 1 mmw.wsgi
```

**3.11 scripts/docker/debugcelery.sh** (replaces `scripts/debugcelery.sh`)
```bash
#!/bin/bash
# Run Celery worker interactively with debug output
set -e
docker compose stop celery
docker compose run --rm celery \
    celery -A 'mmw.celery:app' worker -l debug -n debug@%n
```

**3.12 scripts/docker/debugtiler.sh** (replaces `scripts/debugtiler.sh`)
```bash
#!/bin/bash
# Run tiler with watch mode for development
set -e
docker compose stop tiler
docker compose run --rm --service-ports tiler npm run watch
```

**3.13 scripts/docker/migrate.sh** (convenience wrapper)
```bash
#!/bin/bash
# Run database migrations
set -e
docker compose exec app python manage.py migrate
```

**3.14 scripts/docker/setupdb.sh** (replaces `scripts/aws/setupdb.sh` for local dev)
```bash
#!/bin/bash
# Load geospatial data into PostgreSQL
# Usage: ./scripts/docker/setupdb.sh -b  # load boundary data
#        ./scripts/docker/setupdb.sh -s  # load stream data
set -e

# Parse the same arguments as the original script
usage="$(basename "$0") [-h] [options]
--Sets up a postgresql database for MMW

Options:
    -h  show this help text
    -b  load/reload boundary data
    -s  load/reload stream data
    -d  load/reload DRB stream data
    -m  load/reload mapshed data
    -p  load/reload DEP data
    -c  load/reload catchment data
    -q  load/reload water quality data
"

# Run the setup script inside the app container
docker compose exec app /opt/app/scripts/setupdb.sh "$@"
```

**3.15 scripts/docker/toggle_feature.sh** (replaces `scripts/toggle_feature.sh`)
```bash
#!/bin/bash
# Toggle feature flags
# Usage: ./scripts/docker/toggle_feature.sh subbasin
#        ./scripts/docker/toggle_feature.sh clear
set -e

usage() {
    echo "$(basename "${0}") [OPTION]
    Toggle feature flags

    Options:
    subbasin     Sub-basin modeling
    clear        Clear all features
    "
}

case "$1" in
    subbasin)
        docker compose exec app sh -c 'echo -n "subbasin " >> /tmp/features'
        echo "Enabled subbasin feature. Restart app to apply."
        ;;
    clear)
        docker compose exec app sh -c 'echo -n "" > /tmp/features'
        echo "Cleared all features. Restart app to apply."
        ;;
    *)
        usage
        ;;
esac
```

**3.16 scripts/docker/logs.sh** (new convenience script)
```bash
#!/bin/bash
# View logs for services
# Usage: ./scripts/docker/logs.sh        # all services
#        ./scripts/docker/logs.sh app    # app only
#        ./scripts/docker/logs.sh -f app # follow app logs
docker compose logs "$@"
```

#### Task 4: Create Environment Configuration

**4.1 .env.example**

Create environment template file with all variables documented:

```bash
# Database
MMW_DB_NAME=mmw
MMW_DB_USER=mmw
MMW_DB_PASSWORD=mmw
MMW_DB_HOST=postgres
MMW_DB_PORT=5432

# Redis
MMW_CACHE_HOST=redis
MMW_CACHE_PORT=6379

# Django
DJANGO_SETTINGS_MODULE=mmw.settings.development
DJANGO_SECRET_KEY=development-secret-key-change-in-production
DJANGO_STATIC_ROOT=/var/www/mmw/static
DJANGO_MEDIA_ROOT=/var/www/mmw/media
DJANGO_POSTGIS_VERSION=3.5.0

# Services
MMW_TILER_HOST=tiler
MMW_GEOPROCESSING_HOST=geop
MMW_GEOPROCESSING_PORT=8090
MMW_GEOPROCESSING_VERSION=6.1.0
RWD_HOST=rwd
RWD_PORT=5000

# Stack
MMW_STACK_COLOR=Black
MMW_STACK_TYPE=Development
AWS_REGION=us-east-1

# Optional: OAuth credentials
# MMW_ITSI_CLIENT_ID=
# MMW_ITSI_SECRET_KEY=
# MMW_HYDROSHARE_CLIENT_ID=
# MMW_HYDROSHARE_SECRET_KEY=
```

#### Task 5: Update Django Settings

**5.1 Create `src/mmw/mmw/settings/docker.py`**

Create a new settings module for Docker development that:

- Imports from `development.py`
- Updates database host to use environment variable defaulting to 'postgres'
- Updates cache host to use environment variable defaulting to 'redis'
- Ensures all external service hosts use Docker service names

#### Task 6: Database Initialization

**6.1 Create `docker/postgres/init.sql`**

Create initialization SQL that:

- Creates required extensions (PostGIS, pg_trgm)
- Sets up initial schema if needed

```sql
-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable trigram extension for faster LIKE matches
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Grant ownership to mmw user
ALTER TABLE spatial_ref_sys OWNER TO mmw;
```

**6.2 Adapt data loading for Docker**

The existing `scripts/aws/setupdb.sh` downloads and loads geospatial data from S3:
- Boundary data (counties, HUCs, districts, school districts)
- Stream networks (NHD flowlines, DRB streams, TDX hydro)
- MapShed data
- DEP data (municipalities, urban areas)
- Water quality data
- NHDPlus catchment data

Data source: `https://s3.amazonaws.com/data.mmw.azavea.com/`

Create `scripts/docker/setupdb.sh` that:
- Runs inside the app container (has psql access)
- Downloads compressed SQL files from S3
- Loads data via psql
- Creates trigram indexes for search performance

The script should support the same flags as the original:
```bash
./scripts/docker/setupdb.sh -b  # Boundary data (~small, required)
./scripts/docker/setupdb.sh -s  # Stream data (~medium)
./scripts/docker/setupdb.sh -S  # Hi-res streams (~large)
./scripts/docker/setupdb.sh -d  # DRB streams
./scripts/docker/setupdb.sh -m  # MapShed data
./scripts/docker/setupdb.sh -p  # DEP data
./scripts/docker/setupdb.sh -c  # Catchment data
./scripts/docker/setupdb.sh -q  # Water quality data
```

**6.3 Minimum data for development**

For a functional development environment, load at minimum:
1. Boundary data (`-b`) - Required for drawing AOIs
2. One stream dataset (`-s` or `-d`) - For stream display

Full data loading can take significant time; document which subsets are needed for different features.

#### Task 7: RWD Data Volume

The RWD service requires a large dataset (~512GB in production). For development:

**Option A**: Mount a local directory with sample data
```yaml
volumes:
  - ${RWD_DATA:-./data/rwd}:/opt/rwd-data:ro
```

**Option B**: Use a named volume and populate with `docker cp`

Document the process to obtain or generate sample RWD data for development.

#### Task 8: Update README and Documentation

**8.1 Update README.md**

Add Docker development section that mirrors the existing Vagrant workflow:

```markdown
## Development with Docker

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+
- (Optional) RWD data directory for watershed delineation

### Quick Start

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```

2. Start all services:
   ```bash
   ./scripts/docker/start.sh
   ```

3. Run database migrations:
   ```bash
   ./scripts/docker/migrate.sh
   ```

4. (Optional) Load geospatial data:
   ```bash
   ./scripts/docker/setupdb.sh -b  # Load boundary data
   ```

5. Build frontend assets:
   ```bash
   ./scripts/docker/bundle.sh --vendor
   ./scripts/docker/bundle.sh
   ```

6. Access the application at http://localhost:8000

### Development Commands

| Command | Description |
|---------|-------------|
| `./scripts/docker/start.sh` | Start all services |
| `./scripts/docker/stop.sh` | Stop all services |
| `./scripts/docker/logs.sh [service]` | View service logs |
| `./scripts/docker/shell.sh [service]` | Get a shell in a container |

### Django Commands

| Command | Description |
|---------|-------------|
| `./scripts/docker/manage.sh <command>` | Run Django management command |
| `./scripts/docker/manage.sh shell` | Django shell |
| `./scripts/docker/manage.sh runserver` | Run dev server |
| `./scripts/docker/migrate.sh` | Run migrations |

### Frontend Development

| Command | Description |
|---------|-------------|
| `./scripts/docker/bundle.sh` | Build JS/CSS bundles |
| `./scripts/docker/bundle.sh --watch` | Watch mode with live rebuild |
| `./scripts/docker/bundle.sh --debug` | Build with source maps |
| `./scripts/docker/bundle.sh --vendor` | Build vendor bundle + copy assets |
| `./scripts/docker/yarn.sh <command>` | Run yarn commands |

### Testing

| Command | Description |
|---------|-------------|
| `./scripts/docker/test.sh` | Run full test suite (Python + JS) |
| `./scripts/docker/check.sh` | Run flake8 linting |
| `./scripts/docker/testem.sh` | Run JS tests interactively |

### Debug Mode

For interactive debugging with auto-reload:

| Command | Description |
|---------|-------------|
| `./scripts/docker/debugserver.sh` | Django with gunicorn --reload |
| `./scripts/docker/debugcelery.sh` | Celery with debug logging |
| `./scripts/docker/debugtiler.sh` | Tiler with npm watch |

### Feature Flags

```bash
./scripts/docker/toggle_feature.sh subbasin  # Enable subbasin modeling
./scripts/docker/toggle_feature.sh clear     # Clear all features
```

### Differences from Vagrant

| Vagrant | Docker | Notes |
|---------|--------|-------|
| `vagrant up` | `./scripts/docker/start.sh` | Much faster startup |
| `vagrant ssh app` | `./scripts/docker/shell.sh app` | |
| `vagrant halt` | `./scripts/docker/stop.sh` | |
| `scripts/manage.sh` | `scripts/docker/manage.sh` | Same interface |
| `scripts/bundle.sh` | `scripts/docker/bundle.sh` | Same interface |
| `scripts/test.sh` | `scripts/docker/test.sh` | Same interface |
```

**8.2 Create `doc/arch/adr-008-docker-development.md`**

Document the architectural decision to move from Vagrant to Docker:

```markdown
# ADR-008: Docker Development Environment

## Status
Accepted

## Context
The development environment uses 4 Vagrant VirtualBox VMs which:
- Are slow to provision (30+ minutes)
- Consume significant resources (8GB+ RAM)
- Have divergent configuration from production
- Require Windows/Mac-specific workarounds

## Decision
Replace Vagrant/VirtualBox with Docker Compose for local development:
- Each service runs in its own container
- Source code mounted as volumes for hot-reload
- Same base images used in production (ECS)
- Single `docker compose up` to start everything

## Consequences
### Positive
- Faster startup (seconds vs minutes)
- Lower resource usage
- Closer parity with production
- Simpler CI/CD integration
- Cross-platform consistency

### Negative
- Developers need Docker Desktop (or equivalent)
- Some debugging workflows may differ
- GPU access more complex (if needed)
```

### 5.4 Migration Verification Checklist

Before proceeding to Phase 2, verify:

#### Container Health
- [ ] All containers start successfully (`docker compose ps` shows all healthy)
- [ ] No containers in restart loop
- [ ] Logs show no critical errors (`docker compose logs`)

#### Database & Migrations
- [ ] Database migrations run (`./scripts/docker/migrate.sh`)
- [ ] Boundary data loads (`./scripts/docker/setupdb.sh -b`)
- [ ] PostGIS extension active (`SELECT PostGIS_Version();`)

#### Static Files & Frontend
- [ ] Vendor bundle builds (`./scripts/docker/bundle.sh --vendor`)
- [ ] Main bundle builds (`./scripts/docker/bundle.sh`)
- [ ] Watch mode works (`./scripts/docker/bundle.sh --watch`)
- [ ] Static files collected and served at `/static/`
- [ ] SCSS compiles correctly

#### Application Functionality
- [ ] Homepage loads at `http://localhost:8000`
- [ ] User can log in
- [ ] Map tiles load correctly from tiler service
- [ ] Draw tools work (polygon, rectangle, etc.)

#### Geoprocessing & Analysis
- [ ] Watershed delineation works (draw point, get watershed)
- [ ] Land use analysis completes
- [ ] Soil analysis completes
- [ ] Geoprocessing service responds (`curl http://localhost:8090`)

#### Celery & Background Tasks
- [ ] Celery worker connects to Redis broker
- [ ] Tasks appear in Celery logs
- [ ] Async analysis tasks complete
- [ ] Task results stored correctly

#### Development Workflow
- [ ] Hot-reload works for Django (edit Python file, see change)
- [ ] Hot-reload works for Tiler (npm watch mode)
- [ ] Frontend watch mode rebuilds on JS/SCSS changes
- [ ] Django shell works (`./scripts/docker/manage.sh shell`)

#### Testing
- [ ] Flake8 passes (`./scripts/docker/check.sh`)
- [ ] Django tests pass (`./scripts/docker/manage.sh test --noinput --exclude-tag=mapshed`)
- [ ] JS tests pass (`./scripts/docker/testem.sh ci`)
- [ ] Full test suite passes (`./scripts/docker/test.sh`)

#### Media & File Handling
- [ ] Media file uploads work
- [ ] Uploaded files accessible at `/media/`
- [ ] Media files persist across container restarts

#### Script Parity
- [ ] `scripts/docker/manage.sh` works like `scripts/manage.sh`
- [ ] `scripts/docker/bundle.sh` works like `scripts/bundle.sh`
- [ ] `scripts/docker/yarn.sh` works like `scripts/yarn.sh`
- [ ] `scripts/docker/test.sh` works like `scripts/test.sh`
- [ ] `scripts/docker/debugserver.sh` works like `scripts/debugserver.sh`
- [ ] `scripts/docker/debugcelery.sh` works like `scripts/debugcelery.sh`
- [ ] `scripts/docker/debugtiler.sh` works like `scripts/debugtiler.sh`

---

## 6. Phase 2: Terraform ECS Production Deployment

### 6.1 Overview

Replace Packer AMIs + CloudFormation with Docker images + Terraform for ECS Fargate deployment.

### 6.2 Directory Structure to Create

```
/
├── terraform/
│   ├── environments/
│   │   ├── staging/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── terraform.tfvars
│   │   └── production/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars
│   ├── modules/
│   │   ├── vpc/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ecs-cluster/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ecs-service/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── rds/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── elasticache/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── alb/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ecr/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── s3/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── cloudfront/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── shared/
│       └── backend.tf              # S3 backend configuration
├── .github/
│   └── workflows/
│       ├── docker-build.yml        # Build and push Docker images
│       └── terraform-deploy.yml    # Terraform plan/apply
```

### 6.3 Step-by-Step Implementation Tasks

#### Task 1: Create Production Dockerfiles

Modify development Dockerfiles for production:

**1.1 Production App Dockerfile (`docker/app/Dockerfile.prod`)**

- Use multi-stage build
- Don't mount source as volume
- Copy source code into image
- Run collectstatic during build
- Use production requirements
- Set `DJANGO_SETTINGS_MODULE=mmw.settings.production`
- Optimize for smaller image size

**1.2 Production Tiler Dockerfile (`docker/tiler/Dockerfile.prod`)**

- Don't mount source as volume
- Copy all source code
- Run npm prune --production

#### Task 2: Create ECR Repositories

**2.1 terraform/modules/ecr/main.tf**

Create ECR repositories for:
- `mmw-app` (also used for Celery workers)
- `mmw-tiler`
- `mmw-geop`

Include lifecycle policies to limit stored images.

**Note:** No nginx repository needed. ALB handles HTTPS termination and routing.
S3 + CloudFront handles static/media files.

#### Task 3: Create VPC Module

**3.1 terraform/modules/vpc/main.tf**

Replicate the CloudFormation VPC stack:

- VPC with CIDR `10.0.0.0/16`
- 2 public subnets (for ALB, NAT Gateway)
- 2 private subnets (for ECS tasks, RDS, ElastiCache)
- NAT Gateway (instead of NAT instances for simplicity)
- Internet Gateway
- Route tables

Reference: `deployment/cfn/vpc.py`

#### Task 4: Create RDS Module

**4.1 terraform/modules/rds/main.tf**

Replicate the CloudFormation RDS configuration:

- PostgreSQL 17 (upgrade from 13.4)
- Instance type: `db.t3.micro` (configurable)
- PostGIS extension
- Multi-AZ: optional
- Backup retention: 30 days
- Security group allowing access from ECS tasks

Reference: `deployment/cfn/data_plane.py`

#### Task 5: Create ElastiCache Module

**5.1 terraform/modules/elasticache/main.tf**

Replicate the CloudFormation ElastiCache configuration:

- Redis 7.0 (upgrade from 5.0.6)
- Cluster mode: disabled (single node for staging)
- Automatic failover: enabled for production
- Security group allowing access from ECS tasks

Reference: `deployment/cfn/data_plane.py`

#### Task 6: Create ECS Cluster Module

**6.1 terraform/modules/ecs-cluster/main.tf**

- ECS Cluster with Fargate capacity providers
- Container Insights enabled
- CloudWatch log groups

#### Task 7: Create ECS Service Module

**7.1 terraform/modules/ecs-service/main.tf**

Generic module for ECS services with:

- Fargate task definition
- ECS service with desired count
- Auto-scaling (CPU/memory-based)
- Service discovery (Cloud Map)
- Security groups
- IAM roles (task execution role, task role)
- CloudWatch log configuration

Parameters:
- Container image
- CPU/memory allocation
- Port mappings
- Environment variables
- Health check
- Secrets (from Secrets Manager)

#### Task 8: Create Application Load Balancer Module

**8.1 terraform/modules/alb/main.tf**

- Application Load Balancer
- HTTPS listener with SSL certificate
- HTTP to HTTPS redirect
- Target groups:
  - App target group (default)
  - Tiler target group
- Listener rules:
  - `/tiles/*` → Tiler service
  - `/*` → App service

Reference: `deployment/cfn/application.py` and `deployment/cfn/tiler.py`

#### Task 9: Create S3 Module

**9.1 terraform/modules/s3/main.tf**

Create S3 buckets for:
- Tile cache (`tile-cache.<domain>`)
- Media files (user uploads)
- Static files (optional, can use ECS container)

Configure:
- Public access for tile cache
- CORS for tile cache
- Lifecycle rules

Reference: `deployment/cfn/tile_delivery_network.py`

#### Task 10: Create CloudFront Module

**10.1 terraform/modules/cloudfront/main.tf**

Create CloudFront distribution for:
- Tile caching from S3
- Optional: static file caching

Reference: `deployment/cfn/tile_delivery_network.py`

#### Task 11: Create Environment Configurations

**11.1 terraform/environments/staging/main.tf**

Compose all modules for staging:

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "rds" {
  source = "../../modules/rds"
  vpc_id = module.vpc.vpc_id
  # ...
}

module "elasticache" {
  source = "../../modules/elasticache"
  vpc_id = module.vpc.vpc_id
  # ...
}

module "ecr" {
  source = "../../modules/ecr"
  # ...
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"
  # ...
}

module "alb" {
  source = "../../modules/alb"
  # ...
}

module "app_service" {
  source = "../../modules/ecs-service"
  service_name = "app"
  container_image = "${module.ecr.app_repository_url}:${var.app_version}"
  # ...
}

module "tiler_service" {
  source = "../../modules/ecs-service"
  service_name = "tiler"
  container_image = "${module.ecr.tiler_repository_url}:${var.tiler_version}"
  # ...
}

module "worker_service" {
  source = "../../modules/ecs-service"
  service_name = "worker"
  container_image = "${module.ecr.app_repository_url}:${var.app_version}"
  # ...
}
```

**11.2 terraform/environments/staging/variables.tf**

Define all configurable variables with sensible defaults.

**11.3 terraform/environments/staging/terraform.tfvars**

Set staging-specific values.

#### Task 12: Create CI/CD Pipelines

**12.1 .github/workflows/docker-build.yml**

GitHub Actions workflow to:

1. Build Docker images on push to main/develop
2. Tag with git SHA and branch name
3. Push to ECR
4. Trigger Terraform deployment (optional)

```yaml
name: Build and Push Docker Images

on:
  push:
    branches: [main, develop]
    paths:
      - 'src/**'
      - 'docker/**'
      - 'Dockerfile*'

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [app, tiler, geop, nginx]
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
      - uses: aws-actions/amazon-ecr-login@v2
      - name: Build and push
        run: |
          docker build -f docker/${{ matrix.service }}/Dockerfile.prod -t $ECR_REGISTRY/mmw-${{ matrix.service }}:$GITHUB_SHA .
          docker push $ECR_REGISTRY/mmw-${{ matrix.service }}:$GITHUB_SHA
```

**12.2 .github/workflows/terraform-deploy.yml**

GitHub Actions workflow to:

1. Run `terraform plan` on PR
2. Run `terraform apply` on merge to main (with approval for production)

#### Task 13: Create Secrets Management

**13.1 AWS Secrets Manager**

Store sensitive values:
- `mmw/staging/db-password`
- `mmw/staging/django-secret-key`
- `mmw/staging/oauth-credentials`
- `mmw/production/...`

Reference secrets in ECS task definitions.

#### Task 14: RWD Data Storage

The RWD service requires ~512GB of watershed data. Options for ECS:

**Option A: EFS (Elastic File System)**
- Mount EFS volume to worker tasks
- Pre-populate with RWD data
- Works well with Fargate

**Option B: S3 with caching**
- Store data in S3
- Cache locally in container (limited by task storage)
- May require code changes to RWD service

Recommended: **EFS** for compatibility with existing RWD container.

Create `terraform/modules/efs/main.tf`:
- EFS file system
- Mount targets in private subnets
- Security group allowing NFS from ECS tasks

#### Task 15: Blue/Green Deployment Support

The current system supports Blue/Green deployments. Implement in Terraform:

**Option A: ECS Blue/Green with CodeDeploy**
- Use AWS CodeDeploy for ECS
- Automatic rollback on failures
- Traffic shifting

**Option B: Terraform Workspaces**
- Separate workspaces for blue/green
- Manual traffic switching via ALB

Recommended: **CodeDeploy** for automated rollbacks and traffic management.

### 6.4 Migration Verification Checklist

Before decommissioning EC2:

- [ ] All ECS services running and healthy
- [ ] ALB routing correctly to services
- [ ] Database connectivity from ECS tasks
- [ ] Redis connectivity from ECS tasks
- [ ] Tile caching working (S3 + CloudFront)
- [ ] Geoprocessing tasks execute correctly
- [ ] RWD watershed delineation works
- [ ] Celery tasks complete successfully
- [ ] Static files served correctly
- [ ] Media uploads work (S3)
- [ ] OAuth integrations work
- [ ] SSL certificates configured
- [ ] DNS records updated
- [ ] Monitoring and alerting configured
- [ ] Logs flowing to CloudWatch
- [ ] Auto-scaling working
- [ ] Blue/Green deployment tested

---

## 7. Data Migration Considerations

### 7.1 Database Migration

- RDS can be reused between EC2 and ECS deployments
- No data migration needed for database
- Ensure security groups allow ECS task access

### 7.2 RWD Data

- Current: EBS volume attached to worker EC2 instances
- Target: EFS file system accessible by Fargate tasks
- Migration: Copy data from EBS snapshot to EFS

```bash
# Mount EBS snapshot as volume
# Mount EFS file system
# rsync data from EBS to EFS
```

### 7.3 Static/Media Files

- Current: EC2 local filesystem or S3
- Target: S3 with CloudFront (already partially implemented)
- Ensure Django `DEFAULT_FILE_STORAGE` is set to S3

### 7.4 Environment Variables

- Current: envdir files in `/etc/mmw.d/env/`
- Target: ECS task definition environment variables + Secrets Manager
- Migration: Map all variables from Ansible `group_vars/all` to Terraform variables

---

## 8. Testing Strategy

### 8.1 Phase 1 Testing (Docker Development)

| Test | Description | Expected Result |
|------|-------------|-----------------|
| Container startup | `docker compose up` | All containers healthy |
| Database connection | Django shell `python manage.py dbshell` | Connected to PostgreSQL |
| Redis connection | Django shell cache test | Cache operations work |
| Static files | Visit `/static/` | Files served correctly |
| Homepage | Visit `http://localhost:8000` | Page loads |
| Authentication | Log in with test user | Session created |
| Map tiles | Open map view | Tiles load from tiler |
| Watershed delineation | Draw polygon | RWD returns watershed |
| Geoprocessing | Run land use analysis | Results returned |
| Celery tasks | Trigger async task | Task completes |
| Hot reload | Edit Python file | Changes reflected |
| Frontend build | `yarn bundle` | Bundle created |
| Unit tests | `python manage.py test` | Tests pass |

### 8.2 Phase 2 Testing (ECS Production)

| Test | Description | Expected Result |
|------|-------------|-----------------|
| Terraform plan | `terraform plan` | No errors |
| Terraform apply | `terraform apply` | Resources created |
| ECS services | Check AWS console | All services RUNNING |
| Health checks | ALB target health | All targets healthy |
| HTTPS | Visit `https://staging.domain.com` | SSL works |
| Database | Run Django migrations | Migrations complete |
| End-to-end | Full user workflow | All features work |
| Load test | Concurrent users | Handles expected load |
| Failover | Stop a task | Service recovers |
| Scaling | Increase load | Tasks scale up |
| Deployment | Push new image | Blue/Green works |
| Rollback | Trigger rollback | Previous version restored |

### 8.3 Rollback Plan

#### Phase 1 (Docker)
- Vagrant environment preserved
- Can switch back by using `vagrant up` commands
- No data migration needed (separate databases)

#### Phase 2 (ECS)
- Keep EC2 ASGs at 0 capacity (not terminated)
- DNS can be switched back to EC2 ELBs
- RDS shared between EC2 and ECS (no data loss)

---

## Appendix A: Current Ansible Variable Reference

### From `deployment/ansible/group_vars/all`

| Variable | Value | Usage |
|----------|-------|-------|
| `aws_region` | us-east-1 | AWS region |
| `redis_port` | 6379 | Redis port |
| `postgresql_port` | 5432 | PostgreSQL port |
| `postgresql_version` | 17 | PostgreSQL version |
| `postgis_version` | 3 | PostGIS version |
| `python_version` | 3.10.* | Python version |
| `app_nodejs_version` | 12.11.1 | Node.js for app |
| `tiler_nodejs_version` | 10.16.0 | Node.js for tiler |
| `docker_version` | 5:25.* | Docker version |
| `geop_version` | 6.1.0 | Geoprocessing JAR |
| `celery_version` | 5.4.0 | Celery version |

### From `deployment/ansible/group_vars/development`

| Variable | Value | Usage |
|----------|-------|-------|
| `django_settings_module` | mmw.settings.development | Django settings |
| `redis_bind_address` | 0.0.0.0 | Redis bind |
| `postgresql_listen_addresses` | * | PostgreSQL bind |
| `celery_log_level` | DEBUG | Celery logging |
| `celery_number_of_workers` | 2 | Worker count |

---

## Appendix B: CloudFormation to Terraform Mapping

| CloudFormation Stack | Terraform Module | Notes |
|---------------------|------------------|-------|
| `deployment/cfn/vpc.py` | `terraform/modules/vpc/` | Replace NAT instances with NAT Gateway |
| `deployment/cfn/data_plane.py` | `terraform/modules/rds/` + `terraform/modules/elasticache/` | Split into separate modules |
| `deployment/cfn/application.py` | `terraform/modules/ecs-service/` + `terraform/modules/alb/` | Replace ASG with ECS service |
| `deployment/cfn/worker.py` | `terraform/modules/ecs-service/` + `terraform/modules/efs/` | Add EFS for RWD data |
| `deployment/cfn/tiler.py` | `terraform/modules/ecs-service/` | Replace ASG with ECS service |
| `deployment/cfn/tile_delivery_network.py` | `terraform/modules/s3/` + `terraform/modules/cloudfront/` | Same architecture |

---

## Appendix C: Port Reference

| Service | Internal Port | External Port (Dev) | Protocol |
|---------|--------------|---------------------|----------|
| PostgreSQL | 5432 | 5432 | TCP |
| Redis | 6379 | 6379 | TCP |
| Django (Gunicorn) | 8000 | 8000 | HTTP |
| Tiler (Windshaft) | 4000 | 4000 | HTTP |
| Geoprocessing | 8090 | 8090 | HTTP |
| RWD | 5000 | 5000 | HTTP |
| Livereload | 35729 | 35729 | HTTP/WS |

**Note:** No nginx port (80/443) needed in development. Django serves directly on 8000.

---

## Appendix D: Health Check Endpoints

| Service | Endpoint | Expected Response |
|---------|----------|-------------------|
| Django (Gunicorn) | `GET /health-check/` | HTTP 200 |
| Tiler (Windshaft) | `GET /health-check` | HTTP 200, JSON with db/cache status |
| Geoprocessing | `GET /` or `/health-check` | HTTP 200 |
| RWD | `GET /` | HTTP 200 |
| PostgreSQL | `pg_isready -U mmw` | Exit code 0 |
| Redis | `redis-cli ping` | PONG |

**Note:** In production, ALB performs health checks directly against the service containers.
No nginx layer is needed between ALB and the application.

---

## Appendix E: Script Migration Reference

### Vagrant to Docker Script Mapping

| Vagrant Script | Docker Equivalent | Notes |
|----------------|-------------------|-------|
| `vagrant up` | `./scripts/docker/start.sh` | Much faster, no provisioning |
| `vagrant halt` | `./scripts/docker/stop.sh` | Stops containers |
| `vagrant destroy` | `docker compose down -v` | Removes volumes too |
| `vagrant ssh app` | `./scripts/docker/shell.sh app` | Direct shell access |
| `vagrant ssh worker` | `./scripts/docker/shell.sh celery` | Worker is now `celery` service |
| `vagrant ssh tiler` | `./scripts/docker/shell.sh tiler` | Same name |
| `vagrant ssh services` | `./scripts/docker/shell.sh postgres` | Or `redis` |
| `vagrant provision app` | `docker compose build app` | Rebuild image |
| `vagrant reload app` | `docker compose restart app` | Restart container |

### Development Script Mapping

| Old Script | New Script | Interface Change |
|------------|------------|------------------|
| `scripts/manage.sh` | `scripts/docker/manage.sh` | None - same args |
| `scripts/bundle.sh` | `scripts/docker/bundle.sh` | None - same args |
| `scripts/yarn.sh` | `scripts/docker/yarn.sh` | None - same args |
| `scripts/test.sh` | `scripts/docker/test.sh` | None - same behavior |
| `scripts/testem.sh` | `scripts/docker/testem.sh` | None - same args |
| `scripts/check.sh` | `scripts/docker/check.sh` | None - same behavior |
| `scripts/debugserver.sh` | `scripts/docker/debugserver.sh` | None - same behavior |
| `scripts/debugcelery.sh` | `scripts/docker/debugcelery.sh` | None - same behavior |
| `scripts/debugtiler.sh` | `scripts/docker/debugtiler.sh` | None - same behavior |
| `scripts/toggle_feature.sh` | `scripts/docker/toggle_feature.sh` | None - same args |
| `scripts/aws/setupdb.sh` | `scripts/docker/setupdb.sh` | Same flags supported |

### New Docker-Only Scripts

| Script | Purpose |
|--------|---------|
| `scripts/docker/start.sh` | Start all services |
| `scripts/docker/stop.sh` | Stop all services |
| `scripts/docker/logs.sh` | View container logs |
| `scripts/docker/shell.sh` | Get shell in container |
| `scripts/docker/migrate.sh` | Run Django migrations |

### Environment Differences

| Aspect | Vagrant | Docker |
|--------|---------|--------|
| Config location | `/etc/mmw.d/env/` (envdir) | Environment variables in `.env` |
| Service IPs | Fixed IPs (33.33.34.x) | Docker DNS (service names) |
| Port access | Via forwarded ports | Direct container ports |
| File sync | VirtualBox shared folders | Docker bind mounts |
| Hot reload | Via shared folders | Via bind mounts (faster) |

---

*End of Specification Document*
