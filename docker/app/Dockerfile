FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

ARG NODE_VERSION=12.11.1

WORKDIR /opt/app

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        python3-dev \
        binutils \
        libproj-dev \
        gdal-bin \
        libgdal-dev \
        libpq-dev \
        postgresql-client \
        xvfb \
        chromium \
        curl \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /usr/local --strip-components=1 \
    && npm install -g yarn

COPY src/mmw/requirements /opt/app/requirements
RUN pip install --no-cache-dir -r /opt/app/requirements/development.txt \
    && pip install --no-cache-dir psycopg2-binary awscli

COPY src/mmw/package.json src/mmw/yarn.lock /opt/app/
RUN yarn install --frozen-lockfile

COPY src/mmw /opt/app

ENV DJANGO_SETTINGS_MODULE=mmw.settings.docker \
    DJANGO_SECRET_KEY=development-secret-key \
    DJANGO_STATIC_ROOT=/var/www/mmw/static/ \
    DJANGO_MEDIA_ROOT=/var/www/mmw/media \
    MMW_DB_HOST=postgres \
    MMW_DB_NAME=mmw \
    MMW_DB_USER=mmw \
    MMW_DB_PASSWORD=mmw \
    MMW_CACHE_HOST=redis \
    MMW_CACHE_PORT=6379 \
    MMW_TILER_HOST=tiler:4000 \
    MMW_GEOPROCESSING_HOST=geop \
    MMW_GEOPROCESSING_PORT=8090 \
    RWD_HOST=rwd \
    RWD_PORT=5000

RUN ./bundle.sh --vendor \
    && ./bundle.sh

RUN mkdir -p /var/cache/mmw/static \
    && python manage.py collectstatic --noinput

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "mmw.wsgi"]
