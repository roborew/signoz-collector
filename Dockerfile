# Bakes config.yaml into the image so no host bind-mount of the config is needed.
#
# Coolify remaps relative compose bind mounts (e.g. ./config.yaml) to the app's
# persistent storage dir (/data/coolify/applications/<uuid>/), where the file does
# not exist. Docker then auto-creates the source as an empty directory and the
# container fails to start with a "not a directory" mount error. Building the
# config into the image avoids the bind mount entirely.
#
# busybox provides a static wget for the compose healthcheck — the upstream
# collector image is scratch-based and has no HTTP client.
ARG OTEL_COLLECTOR_VERSION=0.139.0
FROM busybox:1.36.1-uclibc AS busybox
FROM otel/opentelemetry-collector-contrib:${OTEL_COLLECTOR_VERSION}
COPY --from=busybox /bin/busybox /bin/busybox
COPY --from=busybox /bin/wget /bin/wget
COPY config.yaml /etc/otelcol-contrib/config.yaml
# The upstream image's default entrypoint runs the collector with
# --config /etc/otelcol-contrib/config.yaml, so no CMD override is needed.
