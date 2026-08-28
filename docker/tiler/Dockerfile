# node:10.16.0 was based on Debian Stretch (archived/EOL), which caused two problems:
#   1. apt-get required a complex archive.debian.org workaround (slow, unreliable)
#   2. Out-of-date CA certificates caused node-pre-gyp to fail downloading pre-built
#      binaries for @carto/mapnik, forcing a full from-source compilation (30-60 min)
# node:10-buster (Node 10.24.1 on Debian Buster) satisfies windshaft's ^10.15.1
# engine constraint and has up-to-date CA certs so pre-built binaries download correctly.
FROM node:10-buster

WORKDIR /opt/tiler

# Debian Buster reached EOL in June 2024 and its packages were moved to
# archive.debian.org. The `node:10-buster` image still ships with the old
# deb.debian.org sources, so we redirect them before running apt-get.
RUN sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list \
    && sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list \
    && sed -i '/buster-updates/d' /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends \
        libcairo2-dev \
        libpango1.0-dev \
        libjpeg62-turbo-dev \
        libgif-dev \
        libmapnik3.0 \
        libmapnik-dev \
        mapnik-utils \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" \
    && git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/" \
    && git config --global url."https://github.com/".insteadOf "git@github.com:"

COPY src/tiler/package.json src/tiler/package-lock.json /opt/tiler/
RUN npm ci --no-audit

COPY src/tiler /opt/tiler

EXPOSE 4000

CMD ["node", "server.js"]
