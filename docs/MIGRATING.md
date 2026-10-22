# Moving an app to the PHP-FPM image

From `cedyrn/php-parent:8.x-apache`, `8.x-apache-cron` or `8.x-cli` to `cedyrn/php-parent:<version>`. See the [README](../README.md) for how the image works.

## Checklist

1. **Base image:** `FROM cedyrn/php-parent:8.4.27`, the exact version rather than `8.4`.
2. **Run script:** remove it, and set `CMD` to the roles the app needs: `["web"]` (the default, so it can be left out), `["cron"]`, or `["web", "cron"]`. Command-only apps set their own `CMD`.
3. **Crontab:**
   - Copy it to `/etc/supercronic/crontab` rather than `/etc/cron.d/`.
   - Remove the user column (`root`), the `. /root/project_env.sh;` prefix and the `>> /var/log/cron.log 2>&1` redirect. Environment variables are passed to jobs, and output goes to the container logs.
   - Jobs run as `www-data`, not root.
   - Optionally check it during the build with `RUN supercronic -test /etc/supercronic/crontab`.
   - The trailing blank line is no longer needed.
4. **`.htaccess`:** move any `php_value` or `php_flag` lines to a `.user.ini` file in the document root, or to the `PHP_*` environment variables. They cause a 500 error under PHP-FPM.
5. **File ownership:** give `www-data` the directories PHP writes to, rather than `chmod 0777`:
   ```dockerfile
   RUN install -d -o www-data -g www-data -m 0775 writable writable/cache writable/logs writable/session writable/uploads
   ```
6. **Composer stage:** build dependencies with the same image, so platform requirements are checked against the real PHP version and extensions, and drop `--ignore-platform-reqs`.
7. **ECS task definition:**
   - `PHP_FPM_MAX_CHILDREN`, if the default of 10 doesn't suit the app's traffic and memory.
   - `memoryReservation`, if current usage is well above it.
   - The `healthCheck` from the README.
   - For cron services: `stopTimeout` long enough for the longest job to finish, and a deployment configuration with minimum healthy percent 0 and maximum percent 100, so two cron containers never run at once.
8. **Check after deploying:**
   - pages load;
   - login, including HTTP basic auth if the app uses it;
   - form posts and uploads;
   - cron jobs appear in the logs;
   - memory use in CloudWatch compared with before.

## Examples

### CodeIgniter 4 web app

Before:

```dockerfile
FROM composer:2 as composer_stage
...
RUN composer install --ignore-platform-reqs --prefer-dist --no-scripts --no-progress --no-interaction --no-dev --no-autoloader
RUN composer dump-autoload --optimize --apcu --no-dev

FROM cedyrn/php-parent:8.4-apache-cron
WORKDIR /var/www
COPY app /var/www/app
COPY public /var/www/html
...
RUN chmod -R 0777 /var/www/writable
COPY dockerconfig/cronfile /etc/cron.d/app-cron
COPY dockerconfig/run.sh run.sh
EXPOSE 80
CMD ["./run.sh"]
```

After:

```dockerfile
FROM cedyrn/php-parent:8.4.27 AS composer_stage
WORKDIR /build
COPY composer.json composer.lock ./
RUN composer install --prefer-dist --no-scripts --no-progress --no-interaction --no-dev --no-autoloader
COPY app ./app
RUN composer dump-autoload --optimize --apcu --no-dev

FROM cedyrn/php-parent:8.4.27
WORKDIR /var/www

COPY --chown=www-data:www-data app ./app
COPY --chown=www-data:www-data public ./html
COPY --chown=www-data:www-data builds spark ./
COPY --from=composer_stage --chown=www-data:www-data /build/vendor ./vendor
RUN install -d -o www-data -g www-data -m 0775 writable writable/cache writable/logs writable/session writable/uploads \
 && touch .env
```

`CMD` defaults to `["web"]`, so `run.sh`, the empty cronfile and `EXPOSE 80` are no longer needed.

### CodeIgniter 4 cron worker

As the web app, plus:

```dockerfile
COPY dockerconfig/crontab /etc/supercronic/crontab
RUN supercronic -test /etc/supercronic/crontab
CMD ["cron"]
```

with the crontab reduced to:

```cron
*/10 * * * *    php /var/www/spark sys-email-queue:send
5-59/10 * * * * php /var/www/spark application:healthcheck
* * * * *       php /var/www/spark sys-sns:process-deployment
0 * * * *       php /var/www/spark sys-email-queue:check-for-retries
1 0 * * *       php /var/www/spark domains:notify-expiry
```

`run-cmd.sh` and `/root/project_env.sh` are no longer needed.

### Tasks runner

```dockerfile
FROM cedyrn/php-parent:8.4.27

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

RUN apt-get update && apt-get install -y default-mysql-client && rm -rf /var/lib/apt/lists/*

COPY runtasks.sh runtasks.sh
RUN chmod +x runtasks.sh
CMD ["./runtasks.sh"]
```

Commands other than the roles run directly as root, as before. Apache, PHP-FPM and cron are installed but not started.
