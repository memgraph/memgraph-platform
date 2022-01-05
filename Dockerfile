# Lab: Build frontend
FROM node:16 AS lab_frontend
WORKDIR /lab/angular
COPY lab/angular/package*.json ./
RUN npm install
COPY lab/angular/ ./
RUN npm run ng build -- \
    --prod \
    --output-path=/lab/angular/dist

# Lab: Build backend
FROM node:16-alpine AS lab_backend
WORKDIR /lab/app
COPY lab/package*.json ./
RUN npm ci --ignore-scripts
COPY lab/backend/ ./backend/
COPY lab/tsconfig.json .
COPY lab/tsconfig.build.json .
COPY lab/.env .
RUN npm run build

# Memgraph
FROM debian:buster
COPY --from=lab_backend lab /lab
COPY --from=lab_frontend /lab/angular/dist /lab/app/dist-angular

# Commented lines solve the issue of hash mismatches withing debian packages
RUN apt-get clean && \
    # rm -rf /var/lib/apt/lists/* && \
    # echo "Acquire::http::Pipeline-Depth 0;\nAcquire::http::No-Cache true;\nAcquire::BrokenProxy    true;" > /etc/apt/apt.conf.d/99fixbadproxy && \
    # apt-get clean && \
    apt-get update && \
    # apt-get upgrade && \
    apt-get install -f -y \
    python3-setuptools \
    build-essential \
    cmake           \
    curl            \
    g++             \
    git             \
    netcat          \
    libcurl4        \
    libpython3.7    \
    libssl1.1       \
    openssl         \
    python3         \
    python3-pip     \
    python3-dev     \
    supervisor      \
    --no-install-recommends

RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip3 install networkx==2.4 numpy==1.19.2 scipy==1.5.2

RUN curl -L https://download.memgraph.com/memgraph/v2.1.1/debian-10-platform/memgraph_2.1.1-1_amd64.deb > memgraph.deb \
  && dpkg -i memgraph.deb \
  && rm memgraph.deb

# Mage
RUN apt-get update && apt-get install -y \
    clang \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && export PATH="/root/.cargo/bin:${PATH}" \
    && git clone https://github.com/memgraph/mage.git \
    && cd /mage \
    && git checkout main \
    && python3 /mage/setup all \
    && cp -r /mage/dist/* /usr/lib/memgraph/query_modules/ \
    && python3 -m  pip install -r /mage/python/requirements.txt \
    # && rm -rf /mage \
    && rm -rf /root/.rustup/toolchains \
    && apt-get -y --purge autoremove clang \
    && apt-get clean

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

ENV MEMGRAPH=""
CMD /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null & echo "Memgraph Lab is running at localhost:3000\n"; while ! nc -z localhost 7687; do sleep 1; done; /usr/bin/mgconsole
