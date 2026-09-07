# pgrc-agent

**A backup you have never restored is not a backup.**

This is the agent for [pgrestore-check](https://pgrestore-check.fly.dev). It runs
in *your* network, next to your Postgres, and every night it:

1. counts rows on the source,
2. `pg_dump -Fc` the database,
3. counts rows on the source again (live tables move while you dump them),
4. `initdb`s a throwaway Postgres **inside its own container** and `pg_restore`s
   into it,
5. compares row counts and schema-object counts, runs your own boolean SQL
   assertions against the restored copy,
6. POSTs the resulting numbers to the hub, which shouts if a run fails — or if a
   run stops arriving at all.

It is one Python file, stdlib only. Read it: [`pgrc-agent`](./pgrc-agent).

## What leaves your network

The report. Nothing else. Concretely, we receive:

- timings, dump size, database size, Postgres versions
- per table: schema, table name, row count on each side, pass/fail
- counts of tables/indexes/views/sequences/functions/constraints on each side
- the *name* and pass/fail of each check, and for your custom checks the SQL you
  wrote
- the tail of the agent's own log

We never receive your data, a dump, or your credentials. Postgres error messages
are **scrubbed** before sending: libpq does not print passwords, but it does
print the host, its resolved IP, the port, the role and the database, and those
are replaced with `[redacted]`. Check for yourself before trusting any of this:

```bash
docker run --rm -e SOURCE_URL=postgres://... -e PGRC_DRY_RUN=1 \
  ghcr.io/nemanjab17/pgrc-agent:16
```

`PGRC_DRY_RUN=1` prints the exact JSON that would be sent, already scrubbed, and
sends nothing.

## Install

Pick the tag matching your server's Postgres major version. `pg_dump` refuses to
dump a server newer than itself, and restoring a 16 dump into 17 proves the dump
*loads* — not that it restores into 16. Every report states which version it
restored into. There is deliberately no `latest` tag.

```bash
docker run -d --restart=always --name pgrc-agent \
  -e PGRC_HUB=https://pgrestore-check.fly.dev \
  -e PGRC_TOKEN=pgrc_your_token \
  -e SOURCE_URL=postgres://user:pass@db.internal:5432/app \
  -v pgrc-state:/var/lib/pgrc \
  ghcr.io/nemanjab17/pgrc-agent:16
```

**It is a daemon, not a cron job.** On start it asks the hub for the interval you
picked and when it last heard from you, then sleeps until the next run is due. So
changing the schedule needs no redeploy, and a container that restarts does not
re-dump your database. `deploy/pgrc-agent.service` is a systemd unit for the same
thing.

### Environment

| variable | default | meaning |
|---|---|---|
| `SOURCE_URL` | required | `postgres://user:pass@host:5432/db` |
| `PGRC_HUB` | required | hub base URL (not needed with `PGRC_DRY_RUN`) |
| `PGRC_TOKEN` | required | from your dashboard (not needed with `PGRC_DRY_RUN`) |
| `PGRC_ONCE` | off | verify once and exit instead of daemonising |
| `PGRC_DRY_RUN` | off | print the report, send nothing |
| `PGRC_INTERVAL_H` | from hub | override the verification interval |
| `PGRC_TABLES` | 50 | how many of the largest tables to row-count; `0` disables row counting |
| `PGRC_JOBS` | 2 | `pg_restore` parallel jobs |
| `PGRC_CHECK_SQL` | — | file of boolean SQL, one per line, run on the restored copy |
| `PGRC_WORKDIR` | `/tmp` | where the dump and the scratch cluster live |
| `PGRC_STATE` | `/var/lib/pgrc/state.json` | last-run marker |
| `PGRC_KEEP` | off | keep the scratch cluster for debugging |

Exit codes, for one-shot mode: `0` verified and reported, `1` verification
failed, `2` verified but the report never reached the hub (revoked token, quota,
hub down), `3` misconfigured. As a daemon it stays up and logs instead.

### Database role

`pg_dump` needs to read everything. On Postgres 14+ that is a login role with
`pg_read_all_data` — no write permission needed anywhere, and the agent never
writes to your database:

```sql
CREATE ROLE pgrc LOGIN PASSWORD '…';
GRANT pg_read_all_data TO pgrc;
```

### Your own assertions

A restore can come back structurally perfect and still be useless. One boolean
SQL per line in `PGRC_CHECK_SQL`, run against the restored copy — see
[`examples/checks.sql`](./examples/checks.sql):

```sql
SELECT count(*) > 0 FROM users
SELECT NOT EXISTS (SELECT 1 FROM orders o LEFT JOIN customers c ON c.id = o.customer_id WHERE c.id IS NULL)
```

A `PGRC_CHECK_SQL` that points at a file which does not exist is reported as a
**failed** check, never skipped quietly.

## Costs on the source database

Row counting is `count(*)` on the largest `PGRC_TABLES` tables, twice per run
(before and after the dump). On a large busy database that is real I/O — lower
`PGRC_TABLES`, or set it to `0` to rely on the dump/restore and schema checks
alone. The dump itself is a normal `pg_dump`, with the same MVCC snapshot cost as
any other.

Disk: the compressed dump *and* a fully restored copy both live in
`PGRC_WORKDIR`. The agent refuses to start a restore it cannot finish and tells
you how much room it needed.

## Build it yourself

```bash
docker build --build-arg PG_MAJOR=16 -t pgrc-agent:16 .
docker run --rm -e SOURCE_URL=postgres://… -e PGRC_DRY_RUN=1 pgrc-agent:16
```

## Notes

- The scratch cluster runs on a unix socket with `listen_addresses=''`,
  `fsync=off`, and is deleted when the run ends. No docker socket, no second
  server to provision.
- `initdb` refuses to run as root, so the image runs as `postgres`.
- The hub (dashboard, alerting) is not open source today. The agent is the part
  that touches your database, which is why it is the part you can read.

MIT licensed.
