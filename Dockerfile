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
FROM node:12 AS lab
WORKDIR /lab/app
COPY lab/package*.json ./
RUN npm install
COPY lab/lib/ /lab/app/lib/
COPY lab/tsconfig.json .
COPY lab/.env .
RUN npm run build

# Lab: Copy the frontend artifacts
COPY --from=lab_frontend /lab/angular/dist /lab/app/dist-angular

# Memgraph
FROM debian
ARG deb_release
RUN apt-get -oDebug::pkgAcquire::Worker=1 update
RUN apt-get update && apt-get install -y \
    build-essential openssl libcurl4 libssl1.1 python3 libpython3.7 python3-pip supervisor cmake curl git g++ clang \
    --no-install-recommends
  # && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN pip3 install networkx==2.4 numpy==1.19.2 scipy==1.5.2
COPY ${deb_release} /
RUN dpkg -i ${deb_release}

COPY --from=lab lab /lab
COPY mage /mage/
WORKDIR /mage
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN python3 build
RUN cp -r /mage/dist/* /usr/lib/memgraph/query_modules/
# It's required to install python3 because auth module scripts are going to be
# written in python3.
RUN python3 -m  pip install -r /mage/python/requirements.txt

EXPOSE 7687
EXPOSE 3000
RUN apt-get update && apt-get install -y nodejs npm --no-install-recommends
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN usermod -G root memgraph
RUN chmod 777 -r /

CMD ["/usr/bin/supervisord"]

# Works for memgraph
# USER memgraph
# WORKDIR /usr/lib/memgraph
# ENTRYPOINT ["/usr/lib/memgraph/memgraph"]

# Works for lab
# WORKDIR /lab/app
# CMD [ "npm", "run", "start:prod" ]
