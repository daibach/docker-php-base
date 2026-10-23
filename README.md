# docker-php-base

Base PHP images published to Docker Hub as `cedyrn/php-parent`.

| Tags | Image |
|---|---|
| `8.4.27`, `8.4`, `8.5.12`, `8.5` | **PHP-FPM image** (`Dockerfile`): PHP-FPM behind Apache, with cron via supercronic. amd64 and arm64. Use this for new work. |
| `8.x-apache`, `8.x-apache-cron` | **Legacy images** (`legacy/Dockerfile`): mod_php. To be retired once all apps have moved to the PHP-FPM image. See [docs/MIGRATING.md](docs/MIGRATING.md). The `8.3-*` and `*-cli` tags are no longer rebuilt. |

Use the exact version tag (e.g. `cedyrn/php-parent:8.4.27`) in application Dockerfiles, so builds never pick up a stale cached copy of a moving tag.

## PHP-FPM image

Based on the official `php:<version>-fpm` image, with:

- Apache (`mpm_event`) passing PHP requests to PHP-FPM, with `rewrite` and `headers` enabled and `.htaccess` allowed
- PHP extensions: `pdo_mysql`, `mysqli`, `intl`, `zip`, `gd`, `opcache`, `apcu`
- Composer, `install-php-extensions` (to add extensions in an app's Dockerfile), `git`, `zip`, `unzip`, `curl`
- [supercronic](https://github.com/aptible/supercronic) for cron, and [s6-overlay](https://github.com/just-containers/s6-overlay) to supervise processes
- Hardened PHP (`php.ini-production`, `expose_php` off) and Apache (no version in headers or error pages, no `TRACE`)

### Roles

The container's command selects what runs:

| Command | Runs | As |
|---|---|---|
| `web` (default) | Apache and PHP-FPM on port 80 | Apache and FPM workers as `www-data` |
| `cron` | supercronic, using the crontab at `$CRONTAB` | `www-data` |
| `web cron` | both | as above |
| anything else, e.g. `php spark migrate` | that command, directly | `root`, unless the app's Dockerfile sets `USER` |

```dockerfile
FROM cedyrn/php-parent:8.4.27
COPY crontab /etc/supercronic/crontab
CMD ["web", "cron"]
```

For the `web` and `cron` roles:

- Container environment variables reach PHP, for both web requests and cron jobs.
- Logs go to stdout and stderr: Apache access log, PHP and FPM errors, and cron job output.
- If Apache, PHP-FPM or supercronic exits unexpectedly, the container stops so it can be replaced.
- On stop (`SIGTERM`), Apache finishes in-flight requests and supercronic waits for running jobs, for up to 25 seconds. Allow at least 30 seconds before the container is killed (the ECS default).

### Cron

The crontab uses standard 5-field cron syntax, with no user column. supercronic also accepts 7 fields (seconds first, year last) for jobs that run more than once a minute. Jobs run as `www-data` with `/bin/sh`, see the container's environment, and log to the container output.

```cron
*/10 * * * * php /var/www/spark email-queue:send
0 1 * * *    php /var/www/spark log:cleanup
```

A job does not start again while its previous run is still going. The `cron` role fails at start-up if no crontab exists. Check a crontab during an app's build with `RUN supercronic -test /etc/supercronic/crontab`.

### Start-up hooks

Executable files in `/docker-entrypoint.d/` are run in name order, as root, before the `web` and `cron` roles start. A hook that fails stops the container. Hooks are not run for other commands.

### Health checks

`healthcheck` checks the services for the container's roles: `/fpm-ping` through Apache for `web`, and that supercronic is running for `cron`. It always succeeds for other commands. The image's Docker `HEALTHCHECK` uses it. ECS ignores Dockerfile health checks, so for ECS add it to the container definition:

```json
"healthCheck": {
  "command": ["CMD", "healthcheck"],
  "interval": 30,
  "timeout": 10,
  "retries": 3,
  "startPeriod": 15
}
```

`/fpm-ping` returns `pong` and can also be used by a load balancer. `/fpm-status` (FPM worker status) is only available from inside the container. Requests to both are left out of the access log.

### Configuration

Set with environment variables, e.g. in the ECS task definition:

| Variable | Default | |
|---|---|---|
| `APACHE_DOCUMENT_ROOT` | `/var/www/html` | Directory Apache serves |
| `CRONTAB` | `/etc/supercronic/crontab` | Crontab for the `cron` role |
| `SUPERCRONIC_ARGS` | | Extra supercronic flags, e.g. `-json` |
| `PHP_MEMORY_LIMIT` | `128M` | `memory_limit` |
| `PHP_UPLOAD_MAX_FILESIZE` | `2M` | `upload_max_filesize` |
| `PHP_POST_MAX_SIZE` | `8M` | `post_max_size` |
| `PHP_MAX_EXECUTION_TIME` | `30` | `max_execution_time` |
| `PHP_OPCACHE_MEMORY` | `128` | opcache memory in MB |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `0` | Set to `1` when code changes while running, e.g. local development with mounted code |
| `PHP_APCU_MEMORY` | `32M` | APCu shared memory |
| `PHP_FPM_PM` | `ondemand` | FPM process manager: `ondemand`, `dynamic` or `static` |
| `PHP_FPM_MAX_CHILDREN` | `10` | Maximum concurrent PHP requests |
| `PHP_FPM_PROCESS_IDLE_TIMEOUT` | `10s` | `ondemand`: how long idle workers are kept |
| `PHP_FPM_START_SERVERS` / `PHP_FPM_MIN_SPARE_SERVERS` / `PHP_FPM_MAX_SPARE_SERVERS` | `2` / `1` / `3` | `dynamic` only |
| `PHP_FPM_MAX_REQUESTS` | `500` | Requests before a worker is replaced |
| `PHP_FPM_SLOWLOG_TIMEOUT` | `0` (off) | Log requests running longer than this, e.g. `5s` |

`PHP_FPM_MAX_CHILDREN` limits how many PHP requests run at once; further requests wait. Each busy worker uses memory, roughly the memory of one request, so size it to the container's memory. When every worker is busy, FPM logs `server reached max_children setting` to stderr.

With `PHP_FPM_SLOWLOG_TIMEOUT` set, FPM logs a warning to stderr for each request that runs longer, with the script and URI, such as `executing too slow (5.012 sec), logging`. That shows which requests hold workers. A PHP stack trace follows only when the container has the `SYS_PTRACE` capability, which Docker and ECS don't grant by default. Without it, each slow request also logs `ERROR: failed to ptrace(ATTACH) child`, and the `slow requests` count in `/fpm-status` stays at 0. In ECS, add the capability with `"linuxParameters": {"capabilities": {"add": ["SYS_PTRACE"]}}`.

Other PHP settings can be changed with a `.user.ini` file in the document root or an extra `.ini` file in `$PHP_INI_DIR/conf.d/`. `php_value` and `php_flag` in `.htaccess` do not work with PHP-FPM.

Add PHP extensions in an app's Dockerfile with `RUN install-php-extensions redis`.

## PHP versions

`versions.json` lists each supported PHP minor version and the exact patch version it is built from:

```json
{
  "8.4": "8.4.27"
}
```

Images are always built from the exact upstream tag (e.g. `php:8.4.27-fpm`), never the moving `php:8.4-fpm` tag, which can lag behind new releases.

- **Add a PHP version:** add a line to `versions.json` with its latest patch version. All images for it are built automatically.
- **Drop a PHP version:** remove its line. Its existing tags stay on Docker Hub but are no longer rebuilt.

The PHP-FPM image is built for versions from `FPM_MIN_VERSION` in `.github/scripts/fpm-versions.sh` (currently 8.4). The legacy images are built for every version.

### Updates

[Renovate](https://docs.renovatebot.com/) watches for updates and opens PRs:

| Update | Wait after release | Merge |
|---|---|---|
| PHP patch versions in `versions.json` | 1 hour, so every upstream image is published | Automatic once the build passes. Patches released together are grouped. |
| PHP minor and major versions | | Ignored; add them to `versions.json` by hand |
| Composer and `install-php-extensions` (non-major) | 3 days | Automatic once the build passes |
| s6-overlay and supercronic | 3 days | Manual: update the `*_SHA256` build arguments in the `Dockerfile` in the same PR |
| Trivy | 3 days | Manual: update the `*_SHA256` checksums in `.github/actions/setup-trivy/action.yml` in the same PR |
| GitHub Actions (non-major) | | Automatic once the build passes |

**Urgent patches:** open the Dependency Dashboard issue and tick the box to make Renovate check immediately, or edit `versions.json` by hand.

## Builds

Images are built by GitHub Actions (`.github/workflows/build.yml`):

| Trigger | Result |
|---|---|
| Pull request | Builds and tests every image. Nothing is pushed. |
| Push to `main` | Builds, tests and publishes every image. |
| Weekly (Monday 04:00 UTC) | Same as a push to `main`, to pick up upstream Debian updates to the same PHP version. |
| Manual (Actions → Build images → Run workflow) | Same as a push to `main`. Rebuilds the versions already in `versions.json`. |

Each build also applies any Debian security updates, so fixes don't wait for the upstream PHP image to be rebuilt.

The PHP-FPM image is built natively on amd64 and arm64 runners. Each architecture is pushed by digest, without a tag, and that exact image is pulled and tested. A version's tags are only updated when every architecture has passed. Published images include build provenance and an SBOM.

The `Build result` check passes only when every image passes, and is the required status check for `main`.

### Vulnerability scanning

The PHP-FPM image is scanned with [Trivy](https://trivy.dev/). Only vulnerabilities with a fix available are reported; findings never fail a build.

| When | What | Results |
|---|---|---|
| Every build | The image just built, for each architecture | HIGH and CRITICAL findings in the job summary |
| After each build that publishes, and daily at 05:00 UTC (`.github/workflows/scan.yml`) | The published tag for each PHP version (amd64) | All findings in the repository's Security tab, plus HIGH and CRITICAL in the job summary |

Alerts in the Security tab close automatically once a scan no longer finds them. Most findings are fixed by a rebuild (the weekly build, or Actions → Build images → Run workflow) or by updating s6-overlay or supercronic. A vulnerability in a Debian package with no fix is not reported until Debian releases one.

Trivy is downloaded from its GitHub release and checked against a pinned checksum, and it runs after the build has logged out of Docker Hub.

### Tests

`tests/fpm-smoke-test.sh` tests the PHP-FPM image and `tests/smoke-test.sh` the legacy images. Both can be run locally against a built image:

```sh
docker build -t php-parent-test:8.4 --build-arg PHP_VERSION=8.4.27 .
tests/fpm-smoke-test.sh php-parent-test:8.4 8.4.27

docker build -t php-parent-test:8.4-apache --target apache \
  --build-arg PHP_VERSION=8.4.27 --build-arg BASE_TYPE=apache legacy
tests/smoke-test.sh php-parent-test:8.4-apache 8.4.27
```

The optional second argument checks the PHP version. The FPM tests use port 8080 on the host, or `SMOKE_PORT`. The legacy script selects Apache tests when the image name contains `apache`.

### Configuration

The workflow pushes using a Docker Hub personal access token with Read & Write permission:

- `DOCKERHUB_USERNAME`: repository variable
- `DOCKERHUB_TOKEN`: repository secret
