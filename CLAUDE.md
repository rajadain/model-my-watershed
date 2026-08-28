# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Model My Watershed (MMW): a Django + Backbone/Marionette web app for watershed
delineation and hydrology/water-quality modeling (TR-55, GWLF-E, MapShed). The
backend orchestrates several external services rather than doing geoprocessing
itself: a separate Scala/Java `mmw-geoprocessing` service (`geop`), a Node
tile server (`tiler`, Windshaft/Mapnik + TiTiler), and an external Rapid
Watershed Delineation service (`rwd`).

The repo is mid-migration from a 4-VM Vagrant/VirtualBox dev environment to
Docker Compose (see `doc/arch/adr-008-docker-development.md`); both flows
currently coexist. **Prefer the Docker flow** (`scripts/docker/*.sh`) for any
new work — the Vagrant flow (`scripts/*.sh` without the `docker/` prefix) is
being phased out.

## Common commands (Docker)

```bash
./scripts/server.sh                # first-time setup + start the dev environment, ready at http://localhost:8000
```

`scripts/server.sh` copies `.env.example` to `.env` if needed, builds/starts
`postgres`, `redis`, `app`, `celery`, `tiler`, and `geop`, and runs
migrations. It deliberately skips `rwd` (Rapid Watershed Delineation): that
service's published image uses an old manifest format that newer
Docker/containerd builds refuse to pull, and it's optional for most local
work anyway. `./scripts/docker/start.sh` is the lower-level equivalent
(`docker compose up -d` with no service list) — it includes `rwd` and will
fail on affected setups.

Other commands:
```bash
cp .env.example .env               # first-time setup (done automatically by server.sh)
./scripts/docker/start.sh          # start all services (postgres, redis, app, celery, tiler, geop, rwd)
./scripts/docker/migrate.sh        # run Django migrations
./scripts/docker/setupdb.sh -b     # load boundary data (see -h for other datasets: streams, mapshed, water quality...)
./scripts/docker/bundle.sh --vendor && ./scripts/docker/bundle.sh   # build frontend assets (vendor bundle, then app bundle)
```

App runs at http://localhost:8000.

Testing/linting:
```bash
./scripts/docker/test.sh           # full suite: flake8 + Django tests (excludes mapshed tag) + JS tests (testem/xvfb)
./scripts/docker/check.sh          # flake8 only
./scripts/docker/manage.sh test apps.modeling.tests   # single Django app's tests
./scripts/docker/manage.sh test apps.modeling.tests.SomeTestCase.test_thing  # single test
./scripts/docker/manage.sh test_mapshed   # MapShed tests (needs MapShed tables via setupdb.sh)
./scripts/docker/testem.sh         # interactive JS test runner at http://localhost:7357
```
JS lint runs via yarn inside the app container: `./scripts/docker/yarn.sh run lint`.

Other:
```bash
./scripts/docker/manage.sh <cmd>   # any Django management command
./scripts/docker/manage.sh shell
./scripts/docker/shell.sh [service]     # shell into a container (default: app)
./scripts/docker/logs.sh [service]
./scripts/docker/debugserver.sh    # gunicorn --reload, for interactive debugging
./scripts/docker/debugcelery.sh
./scripts/docker/debugtiler.sh     # tiler with npm watch
./scripts/docker/toggle_feature.sh subbasin   # enable a feature flag; toggle_feature.sh clear resets
```

Frontend source lives at `./src/mmw` and is bind-mounted into the `app`
container, so edits are picked up without rebuilding the image — but JS/SCSS
changes still need `bundle.sh` (or `bundle.sh --watch`) to regenerate bundles.
Node dependencies: use `./scripts/docker/yarn.sh add --exact <dep>`, then add
it to the `JS_DEPS` array in `bundle.sh` and rebuild with
`./scripts/docker/bundle.sh --vendor`.

The `tiler` service's `node_modules` is a **named Docker volume**, not
bind-mounted from the host — this is intentional, since it contains native
modules (e.g. `@carto/mapnik`) compiled against the container's `libmapnik`.

## Architecture

### Services (docker-compose.yml)
- `postgres` — PostGIS-enabled Postgres; boundary/stream/mapshed data loaded via `setupdb.sh`.
- `redis` — caching (including geoprocessing result caching, see `MMW_GEOPROCESSING_CACHE`) and Celery broker.
- `app` — Django app (gunicorn in prod-like mode; `debugserver.sh` for `--reload`).
- `celery` — async task worker for long-running modeling/geoprocessing jobs (`mmw/celery.py`, `mmw/tasks.py`).
- `tiler` (`src/tiler`) — Node service serving map tiles (Windshaft + Mapnik styles in `src/tiler/styles/*.mss`, plus a TiTiler-backed raster path).
- `geop` — prebuilt `mmw-geoprocessing` JAR (separate GitHub repo, pulled by version tag in `docker/geop/Dockerfile`); does the actual spatial analysis.
- `rwd` — external Rapid Watershed Delineation image; needs `RWD_DATA` pointed at a local data directory (optional for most work).

### Backend (`src/mmw/apps/`)
Django apps, routed in `src/mmw/mmw/urls.py`:
- `modeling` — core domain: `Project`/`Scenario` models, TR-55 (`modeling/tr55/`) and GWLF-E/MapShed (`modeling/mapshed/`) model implementations, `geoprocessing.py` client for the `geop` service, Celery tasks in `tasks.py`.
- `geoprocessing_api` — public-facing REST API (DRF; Swagger docs at `/api/docs/`) wrapping the modeling/geoprocessing internals for external API clients (throttling, permissions, versioned schemas).
- `bigcz` — Big Cypress/data-catalog search integration.
- `geocode`, `export`, `water_balance` (legacy "micro" site), `user`, `home`, `monitoring`, `core` — supporting apps; `core` holds shared settings/utilities/feature-flag plumbing.
- Settings are layered in `mmw/settings/`: `base.py` -> `development.py`/`production.py` -> `docker.py` (sets container-friendly env defaults, e.g. `MMW_DB_HOST=postgres`, `MMW_TILER_HOST=localhost:4000`). Domain config (layer definitions, GWLF-E defaults/curve numbers) lives in `layer_settings.py` and `gwlfe_settings.py`, not scattered in code.
- Feature flags: written to `/tmp/features` in the app container via `toggle_feature.sh`; read by `core` app to gate in-progress features (e.g. `subbasin`).

### Frontend (`src/mmw/js/src/`)
Backbone.Marionette app (not React), bundled with Browserify + node-sass via `bundle.sh` (invoked through `scripts/docker/bundle.sh`). Organized by feature module, each typically with `models.js`, `views.js`, `controllers.js`, `templates/` (Nunjucks):
`core` (map, layers, shared views), `draw` (AOI drawing), `modeling` (TR-55/GWLF-E UI, includes `modeling/tr55/` and `modeling/gwlfe/` subfolders), `analyze`, `compare`, `data_catalog`, `geocode`, `account`/`user`, `projects`. `app.js`/`main.js` bootstrap the app; `router.js`/`routes.js` define client-side routing.

### Deployment (`deployment/`)
AWS CloudFormation (Troposphere, `deployment/cfn/`) + Ansible (`deployment/ansible/`) provision the production ECS-based stack; Packer (`deployment/packer/`) builds AMIs. Not needed for local development — see `deployment/README.md` and the ADRs in `doc/arch/` (notably `adr-008-docker-ecs-migration-spec.md`) if touching deployment.

## Notes
- Python: Django (older-style class-based views/DRF), flake8-linted, excludes `migrations` from lint.
- JS: ES5-leaning Backbone/Marionette code (not a modern build with JSX/TS); jshint for linting (`.jshintrc`); Mocha/Chai/Sinon for tests, run via Testem.
- Long-running model runs (TR-55/GWLF-E/MapShed jobs) go through Celery, not the request/response cycle — check `apps/modeling/tasks.py` and `mapshed/tasks.py` when touching modeling flows.
- Some datasets loaded by `setupdb.sh` are extremely large (TDX Hydro streams: ~32GB compressed / 110GB uncompressed) — don't load them casually in dev; the boundary/mapshed sets are the common ones needed locally.
