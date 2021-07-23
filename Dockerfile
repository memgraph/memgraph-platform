# Lab: Build frontend
FROM node:12 AS lab_frontend
WORKDIR /lab/angular
COPY lab/angular/package*.json /lab/angular/
RUN npm install
COPY lab/angular/ /lab/angular/
RUN npm run ng build -- \
    --prod \
    --output-path=/lab/angular/dist

# Lab: Build backend
FROM node:12-alpine AS lab_backend
WORKDIR /lab/app
COPY lab/package*.json ./
RUN npm install
COPY lab/lib/ /lab/app/lib/
COPY lab/tsconfig.json .
COPY lab/.env .
RUN npm run build

# Memgraph
FROM debian
RUN apt-get update && apt-get install -y \
    curl \
    git \
    libcurl4 \
    libpython3.7 \
    libssl1.1 \
    nodejs \
    npm \
    openssl \
    python3 \
    python3-pip \
    supervisor \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip3 install networkx==2.4 numpy==1.19.2 scipy==1.5.2

RUN curl https://download.memgraph.com/memgraph/v1.6.0/debian-10/memgraph_1.6.0-community-1_amd64.deb --output memgraph.deb \
  && dpkg -i memgraph.deb \
  && rm memgraph.deb

# Mage
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    cmake \
    g++ \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && export PATH="/root/.cargo/bin:${PATH}" \
    && git clone https://github.com/memgraph/mage.git \
    && cd /mage \
    && python3 /mage/build \
    && cp -r /mage/dist/* /usr/lib/memgraph/query_modules/ \
    && python3 -m  pip install -r /mage/python/requirements.txt \
    && rm -rf /mage \
    && rm -rf /root/.rustup/toolchains \
    && apt-get -y --purge autoremove clang \
    && apt-get clean

COPY --from=lab_backend lab /lab
COPY --from=lab_frontend /lab/angular/dist /lab/app/dist-angular

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# These commands don't work:
# RUN usermod -G root memgraph
# RUN sed -i "$ d" /etc/passwd
# RUN echo "memgraph:x:0:0::/var/lib/memgraph:/bin/bash" >> /etc/passwd

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

CMD ["/usr/bin/supervisord"]
