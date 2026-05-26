# LetsFLUTssh — local test backends

Docker Compose stack that brings up an S3 server, two WebDAV servers
(Basic and Digest auth), a Nextcloud (for Bearer-token auth), and an
SSH/SFTP server on the loopback interface. Use it to exercise the
app's `lfs_core::{s3, webdav, ssh, sftp}` paths against real servers
without renting cloud accounts.

> **Local dev only.** Every service runs with hard-coded credentials
> and accepts plain HTTP. Never expose any of these ports beyond
> 127.0.0.1.

## Default credentials

Everything uses the same credentials:

- Username: `test`
- Password: `test1234`

The 8-character password is dictated by MinIO's `MINIO_ROOT_PASSWORD`
minimum length; every other service in the stack accepts shorter
strings but follows the same dev convention for consistency.

## Prerequisites

- Docker Engine 20.10+ with Compose v2 (`docker compose ...`).
- ~2 GB free RAM (Nextcloud + MariaDB are the heavy services; drop
  the `nextcloud*` services if you don't need Bearer-token testing).
- Ports `9000`, `9001`, `8080`, `8081`, `8082`, `2222` free on host.

## Bring up / tear down

```bash
# From the repo root:
docker compose -f dev/compose/docker-compose.yml up -d

# Watch logs of one service:
docker compose -f dev/compose/docker-compose.yml logs -f minio

# Stop and wipe everything (volumes included):
docker compose -f dev/compose/docker-compose.yml down -v
```

First-time `up` builds the two custom WebDAV images and lets the
`ssh-keygen` init service mint an ed25519 keypair into
`dev/compose/ssh/keys/` (gitignored). Nextcloud takes ~30 s to
finish its own bootstrap before the WebDAV endpoint is reachable.

## Endpoints

| Protocol | URL / host:port | Auth | Notes |
|---|---|---|---|
| S3 (MinIO) | `http://localhost:9000` | `test` / `test1234` | Path-style. Bucket `test-bucket` auto-created by `minio-init`. Console at `http://localhost:9001`. |
| WebDAV Basic | `http://localhost:8080/dav/` | `test` / `test1234` | Apache mod_dav, RFC 7617. |
| WebDAV Digest | `http://localhost:8081/dav/` | `test` / `test1234` | Apache mod_dav, RFC 7616 (MD5, `qop=auth`). |
| WebDAV Bearer | `http://localhost:8082/remote.php/dav/files/test/` | Bearer token (see below) | Nextcloud. |
| SSH / SFTP | `localhost:2222` | `test` / `test1234`, or `dev/compose/ssh/keys/id_ed25519` | linuxserver/openssh-server. |

### Plugging into the app

Open Settings → add a session of the matching kind, then:

**S3 session**

- Endpoint: `http://localhost:9000`
- Region: `us-east-1`
- Path-style: **on**
- Access key id: `test`
- Secret access key: `test1234`
- Default bucket (optional): `test-bucket`

**WebDAV Basic session**

- URL: `http://localhost:8080/dav/`
- Auth: Basic
- Username: `test`
- Password: `test1234`

**WebDAV Digest session**

- URL: `http://localhost:8081/dav/`
- Auth: Digest
- Username: `test`
- Password: `test1234`

**WebDAV Bearer session** (Nextcloud)

1. Open `http://localhost:8082` in a browser. Log in as
   `test` / `test1234`.
2. Settings → Security → "Devices & sessions" → bottom of the page,
   set an app name and click **Create new app password**.
3. Copy the generated token.
4. In the app, configure a WebDAV session:
   - URL: `http://localhost:8082/remote.php/dav/files/test/`
   - Auth: Bearer
   - Token: paste the app-password from step 3.

**SSH / SFTP session (password)**

- Host: `localhost`
- Port: `2222`
- Username: `test`
- Password: `test1234`

**SSH / SFTP session (pubkey)**

- Host: `localhost`
- Port: `2222`
- Username: `test`
- Key file: `dev/compose/ssh/keys/id_ed25519` (absolute path from your
  clone — or paste the PEM contents into the key-text field).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `address already in use` on `up` | Another local server bound the port. Stop it, or override the host port in `docker-compose.yml`. |
| Nextcloud says "Internal Server Error" right after first boot | Bootstrap not finished — wait 30 s, retry. Logs: `docker compose logs nextcloud`. |
| WebDAV Digest returns 401 in a loop | The app sent the wrong realm. Confirm `AuthName` in `webdav-digest/httpd.conf` matches the htdigest realm baked into the image. |
| SSH says `Permission denied (publickey,password)` | The init service didn't finish. Check `dev/compose/ssh/keys/id_ed25519.pub` exists; if not, run `docker compose up ssh-keygen` once. |
| MinIO bucket missing | `minio-init` raced. Re-run it: `docker compose run --rm minio-init`. |

## Reset state for one service

```bash
# WebDAV Basic — wipe just its data volume:
docker compose -f dev/compose/docker-compose.yml down webdav-basic
docker volume rm letsflutssh-dev_webdav-basic-data
docker compose -f dev/compose/docker-compose.yml up -d webdav-basic
```

Same pattern for `webdav-digest-data`, `minio-data`, `nextcloud-data`,
`nextcloud-db`, `sshd-config`.
