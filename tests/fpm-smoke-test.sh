#!/bin/sh
# Checks run against the FPM image before it is pushed.
# Usage: tests/fpm-smoke-test.sh <image> [expected PHP version]
set -eu

IMAGE=$1
EXPECTED_VERSION=${2:-}
PORT=${SMOKE_PORT:-8080}
PREFIX=php-parent-smoke-$$
WORK=$(mktemp -d)

cleanup() {
  for id in $(docker ps -aq --filter "name=^${PREFIX}-"); do
    docker rm -f "$id" >/dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "  ok: $*"
}

run() {
  docker run --rm "$IMAGE" "$@"
}

# Waits until a command succeeds, up to $1 seconds
wait_for() {
  timeout=$1
  shift
  i=0
  until "$@" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -ge "$timeout" ] && return 1
    sleep 1
  done
}

http() {
  curl -sS "$@"
}

# Starts a container with optional files copied in before it starts.
# Usage: start <name> <docker run options...> -- <command...>
start() {
  name=$PREFIX-$1
  shift
  opts=""
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    opts="$opts $1"
    shift
  done
  [ $# -gt 0 ] && shift
  # shellcheck disable=SC2086
  docker create --name "$name" $opts "$IMAGE" "$@" >/dev/null
}

copy_in() {
  docker cp "$2" "$PREFIX-$1:$3"
}

running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$PREFIX-$1")" = "true" ]
}

stopped() {
  ! running "$1"
}

exit_code() {
  docker inspect -f '{{.State.ExitCode}}' "$PREFIX-$1"
}

echo "== Image basics"
VERSION=$(run php -r 'echo PHP_VERSION;')
if [ -n "$EXPECTED_VERSION" ]; then
  [ "$VERSION" = "$EXPECTED_VERSION" ] || fail "PHP $VERSION, expected $EXPECTED_VERSION"
fi
pass "PHP $VERSION"

MODULES=$(run php -m)
for ext in pdo_mysql mysqli intl zip gd apcu "Zend OPcache"; do
  echo "$MODULES" | grep -qx "$ext" || fail "extension $ext not loaded"
done
pass "extensions loaded"

run composer --version >/dev/null 2>&1 || fail "composer not working"
run sh -c 'command -v install-php-extensions' >/dev/null || fail "install-php-extensions missing"
run supercronic -version >/dev/null 2>&1 || run sh -c 'command -v supercronic' >/dev/null || fail "supercronic missing"
pass "composer, install-php-extensions, supercronic present"

[ "$(run php -r 'echo ini_get("expose_php") ? "on" : "off";')" = "off" ] || fail "expose_php is on"
pass "expose_php off"

INFO=$(run cat /etc/php-parent/build.json) || fail "build info missing"
[ "$(run php -r '
  $info = json_decode(file_get_contents("/etc/php-parent/build.json"), true);
  echo $info["php_version"] === PHP_VERSION && strtotime($info["built_at"]) ? "ok" : "bad";
')" = "ok" ] || fail "build info invalid: $INFO"
pass "build info: $(echo "$INFO" | tr -d '\n ')"

echo "== Commands"
set +e
run sh -c 'exit 3'
code=$?
set -e
[ "$code" -eq 3 ] || fail "command exit code $code, expected 3"
[ "$(run id -un)" = "root" ] || fail "commands should run as root"
pass "exit code passed through, runs as root"

echo "== Web role"
cat > "$WORK/index.php" <<'EOF'
<?php echo "smoke-ok";
EOF
cat > "$WORK/info.php" <<'EOF'
<?php
echo json_encode([
    'env' => getenv('SMOKE_VAR'),
    'auth' => $_SERVER['HTTP_AUTHORIZATION'] ?? null,
    'user' => posix_getpwuid(posix_geteuid())['name'],
    'opcache' => (bool) (opcache_get_status(false)['opcache_enabled'] ?? false),
    'apcu' => apcu_enabled(),
]);
EOF
mkdir -p "$WORK/app"
cat > "$WORK/app/.htaccess" <<'EOF'
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.php [L]
EOF
cat > "$WORK/app/index.php" <<'EOF'
<?php echo "front:" . $_SERVER['REQUEST_URI'];
EOF

start web -p "127.0.0.1:$PORT:80" -e SMOKE_VAR=hello
copy_in web "$WORK/index.php" /var/www/html/index.php
copy_in web "$WORK/info.php" /var/www/html/info.php
copy_in web "$WORK/app" /var/www/html/app
docker start "$PREFIX-web" >/dev/null
URL=http://127.0.0.1:$PORT
wait_for 30 curl -fsS "$URL/" || { docker logs "$PREFIX-web"; fail "web role did not start"; }

HEADERS=$(http -D - -o "$WORK/body" "$URL/")
[ "$(cat "$WORK/body")" = "smoke-ok" ] || fail "unexpected body: $(cat "$WORK/body")"
echo "$HEADERS" | grep -qi '^x-powered-by:' && fail "X-Powered-By header present"
echo "$HEADERS" | grep -qi '^server: Apache[[:space:]]*$' || fail "Server header not minimal"
pass "PHP served through FPM with minimal headers"

INFO=$(http -H 'Authorization: Bearer smoke-token' "$URL/info.php")
echo "$INFO" | grep -q '"env":"hello"' || fail "environment variable not passed to PHP: $INFO"
echo "$INFO" | grep -q '"auth":"Bearer smoke-token"' || fail "Authorization header not passed to PHP: $INFO"
echo "$INFO" | grep -q '"user":"www-data"' || fail "FPM workers not running as www-data: $INFO"
echo "$INFO" | grep -q '"opcache":true' || fail "opcache not enabled in FPM: $INFO"
echo "$INFO" | grep -q '"apcu":true' || fail "APCu not enabled in FPM: $INFO"
pass "environment, Authorization, www-data, opcache and APCu"

[ "$(http -o /dev/null -w '%{http_code}' "$URL/missing.php")" = "404" ] || fail "missing .php should be 404"
http "$URL/missing.php" | grep -q "File not found" && fail "missing .php reached FPM"
pass "missing .php returns Apache 404"

[ "$(http "$URL/app/some/route")" = "front:/app/some/route" ] || fail ".htaccess front controller rewrite failed"
pass ".htaccess rewrite"

[ "$(http "$URL/fpm-ping")" = "pong" ] || fail "/fpm-ping did not return pong"
[ "$(http -o /dev/null -w '%{http_code}' "$URL/fpm-status")" = "403" ] || fail "/fpm-status should be refused from outside"
docker exec "$PREFIX-web" curl -fsS -o /dev/null http://127.0.0.1/fpm-status || fail "/fpm-status should work from localhost"
pass "/fpm-ping public, /fpm-status local only"

docker exec "$PREFIX-web" healthcheck || fail "healthcheck failed for web role"
pass "healthcheck"

docker logs "$PREFIX-web" 2>/dev/null | grep -q '"GET / HTTP' || fail "access log missing from stdout"
docker logs "$PREFIX-web" 2>/dev/null | grep -q 'GET /fpm-ping' && fail "/fpm-ping requests should not be logged"
pass "access log on stdout, health checks excluded"

docker stop "$PREFIX-web" >/dev/null
[ "$(exit_code web)" = "0" ] || fail "web role exit code $(exit_code web) on stop"
pass "clean stop"

echo "== Apache waits for FPM at start-up"
start startup -p "127.0.0.1:$PORT:80"
copy_in startup "$WORK/index.php" /var/www/html/index.php
docker start "$PREFIX-startup" >/dev/null
codes=""
i=0
while [ "$i" -lt 300 ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL/" || true)
  codes="$codes $code"
  [ "$code" = "200" ] && break
  i=$((i + 1))
  sleep 0.1
done
[ "$code" = "200" ] || fail "web role did not start:$codes"
case "$codes" in *" 5"*) fail "errors while starting:$codes" ;; esac
docker logs "$PREFIX-startup" 2>&1 | grep -q "AH01079" && fail "Apache could not reach FPM at start-up"
docker rm -f "$PREFIX-startup" >/dev/null
pass "no errors while FPM starts"

echo "== Slow request log"
cat > "$WORK/slow.php" <<'EOF2'
<?php sleep(2); echo "slow-ok";
EOF2
start slowlog -p "127.0.0.1:$PORT:80" -e PHP_FPM_SLOWLOG_TIMEOUT=1s
copy_in slowlog "$WORK/slow.php" /var/www/html/slow.php
docker start "$PREFIX-slowlog" >/dev/null
wait_for 30 curl -fsS "$URL/fpm-ping" || fail "web role with PHP_FPM_SLOWLOG_TIMEOUT did not start"
[ "$(http "$URL/slow.php")" = "slow-ok" ] || fail "slow request failed"
docker logs "$PREFIX-slowlog" 2>&1 | grep -q "script '/var/www/html/slow.php' .* executing too slow" \
  || { docker logs "$PREFIX-slowlog"; fail "slow request not logged"; }
docker rm -f "$PREFIX-slowlog" >/dev/null
pass "PHP_FPM_SLOWLOG_TIMEOUT logs slow requests"

echo "== Document root override"
mkdir -p "$WORK/public"
echo '<?php echo "public-root";' > "$WORK/public/index.php"
start docroot -p "127.0.0.1:$PORT:80" -e APACHE_DOCUMENT_ROOT=/var/www/public
copy_in docroot "$WORK/public" /var/www/public
docker start "$PREFIX-docroot" >/dev/null
wait_for 30 curl -fsS "$URL/" || fail "web role with APACHE_DOCUMENT_ROOT did not start"
[ "$(http "$URL/")" = "public-root" ] || fail "APACHE_DOCUMENT_ROOT not used"
docker rm -f "$PREFIX-docroot" >/dev/null
pass "APACHE_DOCUMENT_ROOT"

echo "== Process failure stops the container"
start crash -- web
docker start "$PREFIX-crash" >/dev/null
wait_for 30 docker exec "$PREFIX-crash" healthcheck || fail "crash test container did not start"
docker exec "$PREFIX-crash" sh -c '
  for p in /proc/[0-9]*; do
    case "$(tr "\0" " " < "$p/cmdline" 2>/dev/null)" in
      "php-fpm: master"*) kill -9 "${p#/proc/}" ;;
    esac
  done'
wait_for 30 stopped crash || fail "container kept running after php-fpm died"
[ "$(exit_code crash)" != "0" ] || fail "container exited 0 after php-fpm died"
pass "container exits ($(exit_code crash)) when php-fpm dies"

echo "== Cron role"
set +e
run cron >/dev/null 2>&1
code=$?
set -e
[ "$code" -ne 0 ] || fail "cron role should fail without a crontab"
pass "cron role fails fast without a crontab"

# supercronic accepts a seconds field, so jobs can run every 2 seconds
cat > "$WORK/crontab" <<'EOF'
*/2 * * * * * * echo "$SMOKE_VAR $(id -un)" >> /tmp/cron-out
EOF
cat > "$WORK/10-hook.sh" <<'EOF'
#!/bin/sh
touch /tmp/hook-ran
EOF
chmod +x "$WORK/10-hook.sh"

start cron -e SMOKE_VAR=hello -- cron
copy_in cron "$WORK/crontab" /etc/supercronic/crontab
copy_in cron "$WORK/10-hook.sh" /docker-entrypoint.d/10-hook.sh
docker start "$PREFIX-cron" >/dev/null
wait_for 30 docker exec "$PREFIX-cron" grep -q "hello www-data" /tmp/cron-out \
  || { docker logs "$PREFIX-cron"; fail "cron job did not run as www-data with the container environment"; }
pass "cron job runs as www-data with the container environment"
docker exec "$PREFIX-cron" test -f /tmp/hook-ran || fail "start-up hook did not run"
pass "start-up hook ran"
docker exec "$PREFIX-cron" healthcheck || fail "healthcheck failed for cron role"
pass "healthcheck"
docker rm -f "$PREFIX-cron" >/dev/null

echo "== Cron waits for running jobs on stop"
cat > "$WORK/crontab" <<'EOF'
*/10 * * * * * * echo start >> /tmp/job; sleep 4; echo done >> /tmp/job
EOF
start graceful -- cron
copy_in graceful "$WORK/crontab" /etc/supercronic/crontab
docker start "$PREFIX-graceful" >/dev/null
wait_for 30 docker exec "$PREFIX-graceful" grep -q start /tmp/job || fail "long-running job did not start"
docker stop -t 20 "$PREFIX-graceful" >/dev/null
docker cp "$PREFIX-graceful:/tmp/job" "$WORK/job"
[ "$(tail -n 1 "$WORK/job")" = "done" ] || fail "running job was interrupted on stop"
[ "$(exit_code graceful)" = "0" ] || fail "cron role exit code $(exit_code graceful) on stop"
pass "running job finished before the container stopped"

echo "== Web and cron roles together"
cat > "$WORK/crontab" <<'EOF'
*/2 * * * * * * echo ran >> /tmp/cron-out
EOF
start both -p "127.0.0.1:$PORT:80" -- web cron
copy_in both "$WORK/crontab" /etc/supercronic/crontab
copy_in both "$WORK/index.php" /var/www/html/index.php
docker start "$PREFIX-both" >/dev/null
wait_for 30 curl -fsS "$URL/" || fail "web did not start alongside cron"
wait_for 30 docker exec "$PREFIX-both" grep -q ran /tmp/cron-out || fail "cron did not run alongside web"
docker exec "$PREFIX-both" healthcheck || fail "healthcheck failed for web and cron roles"
pass "web and cron both running"

echo "PASS: $IMAGE"
