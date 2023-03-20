# For mage
ARG PY_VERSION_DEFAULT=3.9

FROM debian:bullseye as base

ARG TARGETARCH
ARG PY_VERSION_DEFAULT
ENV PY_VERSION ${PY_VERSION_DEFAULT}

# Essentials for production
RUN apt-get update && apt-get install -y \
    libcurl4        `memgraph` \
    libpython${PY_VERSION}   `memgraph` \
    libssl-dev       `memgraph` \
    openssl         `memgraph` \
    build-essential `mage-memgraph` \
    cmake           `mage-memgraph` \
    curl            `mage-memgraph` \
    g++             `mage-memgraph` \
    python3         `mage-memgraph` \
    python3-pip     `mage-memgraph` \
    python3-setuptools     `mage-memgraph` \
    python3-dev     `mage-memgraph` \
    clang           `mage-memgraph` \
    git             `mage-memgraph` \
    supervisor      `memgraph`\
    netcat         `memgraph-platform` \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

###################################################################################################################################################

# MAGE
FROM base as mage-dev

WORKDIR /mage
COPY mage /mage

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install --default-timeout=1000 -r /mage/python/requirements.txt

RUN python3 -m pip --default-timeout=1000 --no-cache-dir install torch-sparse torch-cluster torch-spline-conv \
    torch-geometric torch-scatter -f https://data.pyg.org/whl/torch-1.12.0+cu102.html

RUN python3 /mage/setup build -p /usr/lib/memgraph/query_modules/

# DGL build from source
RUN git clone --recurse-submodules -b 0.9.x https://github.com/dmlc/dgl.git  \
    && cd dgl && mkdir build && cd build && cmake .. \
    && make -j4 && cd ../python && python3 setup.py install

###################################################################################################################################################

# Lab: Build backend
FROM node:16-alpine as lab-base

WORKDIR /app
# Python make and g++ are needed for arm node-gyp package
RUN apk update && apk add git python3 make g++
ARG NPM_PACKAGE_TOKEN

COPY lab/frontend/.npmrc ./frontend/
COPY lab/frontend/package*.json ./frontend/
COPY lab/frontend/memgraph-orb-*.tgz ./frontend/
RUN echo '//npm.pkg.github.com/:_authToken=${NPM_PACKAGE_TOKEN}' | tee -a ./frontend/.npmrc

COPY lab/package*.json ./

RUN npm config rm proxy
RUN npm config rm https-proxy
RUN npm config set legacy-peer-deps true
RUN npm install && npm cache clean --force
RUN rm -f ./frontend/.npmrc

COPY lab/tsconfig.json .
COPY lab/tsconfig.build.json .
COPY lab/.env .

COPY lab/backend/ ./backend/
COPY lab/frontend/ ./frontend/

RUN npm run build

RUN cd frontend && npm run build:production

###################################################################################################################################################

FROM base as final

# Copy the backend artifacts
COPY --from=lab-base /app/dist-backend /lab/dist-backend
COPY --from=lab-base /app/dist-frontend /lab/dist-frontend

COPY --from=lab-base /app/node_modules /lab/node_modules
COPY --from=lab-base /app/.env /lab/.env

# This is needed for lab
RUN apt-get update \
    && curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# This is needed for memgraph built in algos
RUN pip3 install --default-timeout=1000 networkx==2.4 numpy==1.21.4 scipy==1.7.3

RUN sed -i "s/HOTJAR_IS_ENABLED=false/HOTJAR_IS_ENABLED=true/" /lab/.env

#copy modules
COPY --from=mage-dev /usr/lib/memgraph/query_modules/ /usr/lib/memgraph/query_modules/

#copy python build
COPY --from=mage-dev /usr/local/lib/python${PY_VERSION}/ /usr/local/lib/python${PY_VERSION}/

COPY memgraph-${TARGETARCH}.deb .

RUN dpkg -i memgraph-${TARGETARCH}.deb && rm memgraph-${TARGETARCH}.deb

RUN rm -rf /mage \
    && export PATH="/usr/local/lib/python${PY_VERSION}:${PATH}" \
    && apt-get -y --purge autoremove clang git curl python3-pip python3-dev cmake build-essential \
    && apt-get clean

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

ENV MEMGRAPH=""
ENV MGCONSOLE=""

CMD /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null \
    & echo "Memgraph Lab is running at localhost:3000\n"; \
    while ! nc -z localhost 7687; do sleep 1; done; /usr/bin/mgconsole $MGCONSOLE
