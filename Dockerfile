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
FROM debian:buster
COPY --from=lab_backend lab /lab
COPY --from=lab_frontend /lab/angular/dist /lab/app/dist-angular

RUN apt-get update && apt-get install -y \
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
    nodejs          \
    npm             \
    openssl         \
    python3         \
    python3-pip     \
    python3-dev     \
    supervisor      \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip3 install networkx==2.4 numpy==1.19.2 scipy==1.5.2

# RUN curl https://download.memgraph.com/memgraph/v2.0.0/debian-10/memgraph_2.0.0-1_amd64.deb --output memgraph.deb \
RUN curl -L download.memgraph.com/memgraph/v2.0.0/debian-10-platform/memgraph_2.0.0+3~a7dab1fd-1_amd64.deb --output memgraph.deb \
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
    && git checkout new_query_modules_api \
    && python3 /mage/setup all \
    && cp -r /mage/dist/* /usr/lib/memgraph/query_modules/ \
    && python3 -m  pip install -r /mage/python/requirements.txt \
    # && rm -rf /mage \
    && rm -rf /root/.rustup/toolchains \
    && apt-get -y --purge autoremove clang \
    && apt-get clean

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# These commands don't work:
# RUN usermod -G root memgraph
# RUN sed -i "$ d" /etc/passwd
# RUN echo "memgraph:x:0:0::/var/lib/memgraph:/bin/bash" >> /etc/passwd

# RUN chown -hR root /usr/lib/memgraph
RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

CMD /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null & while ! nc -z localhost 7687; do sleep 1; done; /usr/bin/mgconsole
# CMD /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null
