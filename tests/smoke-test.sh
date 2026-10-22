#!/bin/sh
# Basic checks run against each image before it is pushed.
# Usage: tests/smoke-test.sh <image>
set -eu

IMAGE=$1
CONTAINER=php-parent-smoke-$$
PORT=${SMOKE_PORT:-8080}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run() {
  docker run --rm -e COMPOSER_ALLOW_SUPERUSER=1 "$IMAGE" "$@"
}

echo "== PHP version"
run php -v

echo "== PHP extensions"
MODULES=$(run php -m)
for ext in pdo_mysql mysqli intl; do
  echo "$MODULES" | grep -qx "$ext" || fail "extension $ext not loaded"
done

echo "== Composer"
run composer --version

case "$IMAGE" in
  *apache*)
    echo "== Apache config"
    run apache2ctl -t

    echo "== Apache serves PHP"
    trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT
    docker run -d --name "$CONTAINER" -p "127.0.0.1:$PORT:80" "$IMAGE" >/dev/null
    docker exec "$CONTAINER" sh -c 'echo "<?php echo \"smoke-ok\";" > /var/www/html/index.php'

    for _ in $(seq 1 30); do
      curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
      sleep 1
    done

    HEADERS=$(curl -fsS -D - -o /tmp/smoke-body-$$ "http://127.0.0.1:$PORT/") \
      || { docker logs "$CONTAINER"; fail "no response from Apache"; }
    BODY=$(cat /tmp/smoke-body-$$)
    rm -f /tmp/smoke-body-$$

    [ "$BODY" = "smoke-ok" ] || fail "unexpected body: $BODY"
    echo "$HEADERS" | grep -qi '^x-powered-by:' && fail "X-Powered-By header present"
    echo "$HEADERS" | grep -qi '^server: Apache[[:space:]]*$' || fail "Server header not minimal: $(echo "$HEADERS" | grep -i '^server:')"
    ;;
esac

echo "PASS: $IMAGE"
