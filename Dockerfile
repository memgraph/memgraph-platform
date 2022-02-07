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
FROM dokken/centos-stream-9
COPY --from=lab_backend lab /lab
COPY --from=lab_frontend /lab/angular/dist /lab/app/dist-angular

ARG MEMGRAPH_RPM

# Commented lines solve the issue of hash mismatches withing debian packages
RUN dnf install -y 'dnf-command(config-manager)' && dnf config-manager --set-enabled crb \ 
    && dnf install -y \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm
RUN yum clean all && \
    # rm -rf /var/lib/apt/lists/* && \
    # echo "Acquire::http::Pipeline-Depth 0;\nAcquire::http::No-Cache true;\nAcquire::BrokenProxy    true;" > /etc/apt/apt.conf.d/99fixbadproxy && \
    # yum clean && \
    yum update && \
    # apt-get upgrade && \
    yum install -y \
    python3-setuptools \
    epel-release \
    make \
    cmake           \
    curl            \
    g++             \
    git             \
    nc          \
    libcurl        \
    openssl-devel   \
    libuuid-devel  \
    openssl         \
    python3         \
    python3-pip     \
    python3-devel     \
    --nobest --allowerasing

RUN pip3 install supervisor

RUN yum install -y nodejs \
    && rm -rf /tmp/* /var/tmp/*

RUN pip3 install networkx==2.4 numpy==1.21.1 scipy==1.7.1

COPY ${MEMGRAPH_RPM} /

RUN rpm -i ${MEMGRAPH_RPM} && rm ${MEMGRAPH_RPM}

# Mage
RUN yum update -y && yum install -y \
    clang \
    --nobest --allowerasing \
    && rm -rf /tmp/* /var/tmp/* \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && export PATH="/root/.cargo/bin:${PATH}" \
    && git clone https://github.com/memgraph/mage.git \
    && cd /mage \
    && git checkout MG-fix-build-for-centos-9 \
    && python3 -m  pip install -r /mage/python/requirements.txt \
    && python3 /mage/setup all \
    && cp -r /mage/dist/* /usr/lib/memgraph/query_modules/ \
    # && rm -rf /mage \
    && rm -rf /root/.rustup/toolchains \
    && yum -y remove clang \
    && yum clean all

EXPOSE 3000 7687
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod 777 -R /var/log/memgraph
RUN chmod 777 -R /var/lib/memgraph
RUN chmod 777 -R /usr/lib/memgraph
RUN chmod 777 /usr/lib/memgraph/memgraph

ENV MEMGRAPH=""
CMD /usr/local/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf >> /dev/null & echo "Memgraph Lab is running at localhost:3000\n"; while ! nc -z localhost 7687; do sleep 1; done; /usr/bin/mgconsole
