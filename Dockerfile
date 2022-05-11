# Lab: Build backend
FROM node:16-alpine as lab-base

WORKDIR /app
# Python make and g++ are needed for arm node-gyp package
RUN apk update && apk add git python3 make g++
ARG NPM_PACKAGE_TOKEN

COPY lab/frontend/.npmrc ./frontend/
COPY lab/frontend/package*.json ./frontend/
RUN echo '//npm.pkg.github.com/:_authToken=${NPM_PACKAGE_TOKEN}' | tee -a ./frontend/.npmrc

COPY lab/package*.json ./

RUN npm config rm proxy
RUN npm config rm https-proxy
RUN npm install && npm cache clean --force
RUN rm -f ./frontend/.npmrc

COPY lab/tsconfig.json .
COPY lab/tsconfig.build.json .
COPY lab/.env .

COPY lab/backend/ ./backend/
COPY lab/frontend/ ./frontend/

RUN npm run build

RUN cd frontend && npm run build:production

FROM debian:bullseye
# Copy the backend artifacts
COPY --from=lab-base /app/dist-backend /lab/dist-backend
COPY --from=lab-base /app/dist-frontend /lab/dist-frontend

COPY --from=lab-base /app/node_modules /lab/node_modules
COPY --from=lab-base /app/.env /lab/.env

RUN sed -i "s/HOTJAR_IS_ENABLED=false/HOTJAR_IS_ENABLED=true/" /lab/.env

# Building Mage and Memgraph
RUN apt-get clean && \
  apt-get update && \
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

RUN pip3 install networkx==2.4 numpy==1.21.4 scipy==1.7.3

ARG TARGETARCH

# Install memgraph
COPY memgraph-${TARGETARCH}.deb .
RUN dpkg -i memgraph-${TARGETARCH}.deb && rm memgraph-${TARGETARCH}.deb

# Mage
RUN apt-get update && apt-get install -y \
  clang uuid-dev \
  --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="${PATH}:/root/.cargo/bin"

COPY mage /mage
RUN cd /mage \
  && python3 setup build -p /usr/lib/memgraph/query_modules/ \
  && python3 -m  pip install -r /mage/python/requirements.txt \
  && rm -rf /root/.rustup/toolchains \
  && apt-get -y --purge autoremove clang \
  && apt-get clean \
  && rm -rf /mage

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

ENV MEMGRAPH=""
ENV MGCONSOLE=""

CMD /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null & echo "Memgraph Lab is running at localhost:3000\n"; while ! nc -z localhost 7687; do sleep 1; done; /usr/bin/mgconsole $MGCONSOLE
