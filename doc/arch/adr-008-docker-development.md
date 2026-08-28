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
