FROM postgres:18.6

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
       postgresql-18-cron \
       postgresql-18-partman \
    && rm -rf /var/lib/apt/lists/*

