# One image per Postgres major: the tools must be >= the server being dumped.
ARG PG_MAJOR=16
FROM postgres:${PG_MAJOR}-alpine

RUN apk add --no-cache python3
COPY pgrc-agent /usr/local/bin/pgrc-agent

# The daemon keeps a last-run marker here so a restart loop cannot re-dump the
# source every few seconds. Mount a volume on it to survive container replacement
# (not required: the hub's last_report_at is the authoritative schedule).
RUN mkdir -p /var/lib/pgrc && chown postgres /var/lib/pgrc
VOLUME /var/lib/pgrc

# initdb refuses to run as root, and the scratch cluster lives in a tmpdir.
USER postgres
WORKDIR /tmp
ENV PGRC_WORKDIR=/tmp
ENTRYPOINT ["python3", "/usr/local/bin/pgrc-agent"]
