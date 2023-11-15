# Lab: Build backend
FROM node:18.15-alpine as lab-base

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

RUN sed -i "s/NODE_ENV=local/NODE_ENV=platform/" ./.env

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

# Building and Memgraph
RUN apt-get clean && \
  apt-get update && \
  apt-get install -f -y \
  python3-setuptools \
  build-essential \
  cmake           \
  curl            \
  git             \
  netcat          \
  libcurl4        \
  libssl1.1       \
  openssl         \
  python3         \
  python3-pip     \
  python3-dev     \
  supervisor      \
  --no-install-recommends

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip3 install networkx==2.4 numpy==1.21.4 scipy==1.7.3

ARG TARGETARCH

# Install memgraph
COPY memgraph-${TARGETARCH}.deb .
RUN dpkg -i memgraph-${TARGETARCH}.deb && rm memgraph-${TARGETARCH}.deb

EXPOSE 3000 7444 7687
COPY configs/ /etc/supervisor/

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

ENV MEMGRAPH="--also-log-to-stderr"

ENTRYPOINT [ "/usr/bin/supervisord" ]
CMD [ "-c", "/etc/supervisor/supervisord.conf" ]
