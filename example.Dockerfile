FROM memgraph/memgraph-platform:2.8.0-memgraph2.8.0-lab2.6.0-mage1.7

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
         procps vim curl gnupg libaio1 libaio-dev tzdata\
  && apt-get autoremove -yqq --purge \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY mssql-release.gpg  /etc/apt/trusted.gpg.d
COPY mssql-release-deb.list /etc/apt/sources.list.d

# TODO(gitbuda): ACCEPT_EULA probably has to be on the user side -> figure out how to do that with Docker.
RUN apt-get update \
  && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
  && ACCEPT_EULA=Y apt-get install -y mssql-tools18 \
  && apt-get install -y unixodbc-dev \
  && apt-get install -y libgssapi-krb5-2
RUN apt upgrade -y

COPY getpip.py /tmp
RUN /usr/bin/python3 /tmp/getpip.py

RUN pip install oracledb
RUN pip install mysql-connector-python
RUN pip install pyodbc

# TODO(gitbuda): Define what's the proper way to set timezone on the server.
# NOTE: Memgraph will take data from the server, since timezones are not yet supported, the timezone should be UTC?
RUN echo "Etc/UTC" > /etc/timezone
RUN dpkg-reconfigure -f noninteractive tzdata

COPY module.py /usr/lib/memgraph/query_modules
