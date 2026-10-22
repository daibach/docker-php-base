# docker-php-base

Base PHP images published to Docker Hub as `cedyrn/php-parent:<minor>-<variant>`, e.g. `cedyrn/php-parent:8.4-apache-cron`.

| Variant | Contents |
|---|---|
| `apache` | Official `php:<version>-apache` image (mod_php) with common extensions, hardened PHP and Apache config, and Composer |
| `apache-cron` | As `apache`, with `/var/log/cron.log` created |
| `cli` | Official `php:<version>-cli` image with common extensions, hardened PHP config, and Composer |

All variants are built from `legacy/Dockerfile` using `--target <variant>`.

## PHP versions

`versions.json` lists each supported PHP minor version and the exact patch version it is built from:

```json
{
  "8.4": "8.4.27"
}
```

Images are always built from the exact upstream tag (e.g. `php:8.4.27-apache`), never the moving `php:8.4-apache` tag, which can lag behind new releases.

- **Add a PHP version:** add a line to `versions.json` with its latest patch version. All variants for it are built automatically.
- **Drop a PHP version:** remove its line. Its existing tags stay on Docker Hub but are no longer rebuilt.

### Patch releases

[Renovate](https://docs.renovatebot.com/) watches `versions.json` for new PHP patch versions on Docker Hub:

- It waits an hour after a new patch tag is published, so that every upstream variant is available.
- It opens a PR, grouping patches released together, and enables auto-merge. The PR merges once the build passes, and the merge pushes updated images.
- New PHP minor and major versions are ignored; add those to `versions.json` by hand.

Non-major updates to GitHub Actions used by the workflow are also auto-merged. Major updates get a PR for review.

**Urgent patches:** open the Dependency Dashboard issue and tick the box to make Renovate check immediately, or edit `versions.json` by hand.

## Builds

Images are built by GitHub Actions (`.github/workflows/build.yml`):

| Trigger | Result |
|---|---|
| Pull request | Builds and tests every image. Nothing is pushed. |
| Push to `main` | Builds, tests and pushes every image. |
| Weekly (Monday 04:00 UTC) | Same as a push to `main`, to pick up upstream Debian updates to the same PHP version. |
| Manual (Actions → Build images → Run workflow) | Same as a push to `main`. Rebuilds the versions already in `versions.json`. |

Each image is checked by `tests/smoke-test.sh` before it is pushed. If a test fails, that image's tag is not updated. The script can be run locally against a built image:

```sh
docker build -t php-parent-test:8.4-apache --target apache \
  --build-arg PHP_VERSION=8.4.27 --build-arg BASE_TYPE=apache legacy
tests/smoke-test.sh php-parent-test:8.4-apache 8.4.27
```

Apache tests are selected when the image name contains `apache`. The optional second argument checks the PHP version.

The `Build result` check passes only when every image passes, and is the required status check for `main`.

### Configuration

The workflow pushes using a Docker Hub personal access token with Read & Write permission:

- `DOCKERHUB_USERNAME`: repository variable
- `DOCKERHUB_TOKEN`: repository secret
