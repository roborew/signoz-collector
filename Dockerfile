# Debian wrapper around the upstream collector binary so Infisical CLI can inject
# secrets at runtime (upstream otel/opentelemetry-collector-contrib is scratch).
#
# config.yaml is baked into the image — Coolify remaps relative compose bind
# mounts to app storage where the file is missing, which fails. Do not bind-mount it.
#
# wget is installed for the compose healthcheck.

ARG OTEL_COLLECTOR_VERSION=0.139.0

FROM otel/opentelemetry-collector-contrib:${OTEL_COLLECTOR_VERSION} AS otelcol

FROM debian:bookworm-slim

ARG OTEL_COLLECTOR_VERSION=0.139.0
ARG INFISICAL_CLI_VERSION=0.43.84

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl wget \
  && ARCH="$(dpkg --print-architecture)" \
  && case "$ARCH" in \
    amd64) INFISICAL_ARCH=amd64 ;; \
    arm64) INFISICAL_ARCH=arm64 ;; \
    *) echo "unsupported dpkg arch for Infisical CLI: $ARCH" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://github.com/Infisical/cli/releases/download/v${INFISICAL_CLI_VERSION}/infisical_${INFISICAL_CLI_VERSION}_linux_${INFISICAL_ARCH}.deb" -o /tmp/infisical.deb \
  && dpkg -i /tmp/infisical.deb \
  && rm -f /tmp/infisical.deb \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=otelcol /otelcol-contrib /otelcol-contrib
COPY config.yaml /etc/otelcol-contrib/config.yaml
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV INFISICAL_DISABLE_UPDATE_CHECK=true

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/otelcol-contrib", "--config=/etc/otelcol-contrib/config.yaml"]
