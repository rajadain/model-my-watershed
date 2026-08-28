FROM node:10.16.0

WORKDIR /opt/tiler

RUN sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list \
    && sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list \
    && sed -i '/stretch-updates/d' /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=true update \
    && apt-get install -y --no-install-recommends --allow-unauthenticated \
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

COPY src/tiler/package.json /opt/tiler/
RUN npm install

COPY src/tiler /opt/tiler

EXPOSE 4000

CMD ["node", "server.js"]
