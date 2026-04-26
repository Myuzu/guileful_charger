FROM postgres:18.3

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
       postgresql-18-cron \
       postgresql-18-partman \
    && rm -rf /var/lib/apt/lists/*

