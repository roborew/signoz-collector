# SigNoz collection agent (Coolify)

One OpenTelemetry Collector per Docker host. Collects host metrics, container metrics, and container logs, and receives application OTLP (traces / metrics / logs), then exports everything to self-hosted SigNoz over OTLP/HTTP (typically HTTPS via Cloudflare).

Deploy this stack with Coolify’s Docker Compose build pack. `config.yaml` is baked into the image — do not bind-mount it.

## Data flow

```
App containers (Coolify, bridge network)
  → http://host.docker.internal:4318  (OTLP/HTTP on the Docker host)
  → signoz-collection-agent (network_mode: host)
  → https://otel.roborew.xyz          (SIGNOZ_OTLP_ENDPOINT)
  → SigNoz
```

The collector uses `network_mode: host`, so it has **no** Docker service DNS name. Coolify “shared network” attach cannot reach it by container name. Apps on the same host must send OTLP to the **host gateway** (`host.docker.internal`), not `localhost` inside the app container and not the public SigNoz hostname.

| Piece | Value |
| --- | --- |
| App → collector | `http://host.docker.internal:4318` (HTTP; prefer over gRPC) |
| Host alias | `extra_hosts: ["host.docker.internal:host-gateway"]` on each instrumented service |
| Headers | Omit / unset `OTEL_EXPORTER_OTLP_HEADERS` (self-hosted via this collector) |
| Service name | Unique per process via `OTEL_SERVICE_NAME` |

gRPC on `:4317` is available if your SDK exports gRPC; this guide standardizes on HTTP `:4318`.

## Env var contract

Two namespaces. Do not mix them.

### Collector (this Coolify resource)

Set these on the **collection agent** only (see [`.env.example`](.env.example)).

| Variable | Required | Example | Role |
| --- | --- | --- | --- |
| `SIGNOZ_OTLP_ENDPOINT` | yes | `https://otel.roborew.xyz` | Where **this collector** exports (OTLP/HTTP base URL) |
| `SIGNOZ_HOST` | yes (compose) | `otel.roborew.xyz` | Hostname / fallback for endpoint default |
| `SIGNOZ_INGESTION_KEY` | no | _(empty)_ | SigNoz Cloud only; leave empty for self-hosted |
| `DEPLOYMENT_ENVIRONMENT` | recommended | `prod-coolify-host-01` | Host resource attribute (`OTEL_RESOURCE_ATTRIBUTES`) |
| Tuning vars | optional | see `.env.example` | `HOSTMETRICS_*`, `DOCKER_STATS_*`, `MEMORY_LIMITER_*`, etc. |

### Application containers (every instrumented app on the same host)

Set these on **app** services — never on the collector.

| Variable | Required | Value | Role |
| --- | --- | --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | yes | `http://host.docker.internal:4318` | App → **local collector** (not SigNoz) |
| `OTEL_SERVICE_NAME` | yes | unique per process | Service name in SigNoz UI |
| `OTEL_EXPORTER_OTLP_HEADERS` | must unset | — | Not needed for self-hosted via collector |
| `OTEL_RESOURCE_ATTRIBUTES` | optional | e.g. `deployment.environment=production` | Extra resource attributes |

**Alignment rules**

- Apps never set `SIGNOZ_*`. Those are collector-only.
- Apps never set the public SigNoz URL as `OTEL_EXPORTER_OTLP_ENDPOINT` when using this collector.
- Prefer Compose/Coolify for the host-local endpoint (not a secret). If the app uses Infisical (`infisical run`), either put `OTEL_*` only in Infisical **or** only in Compose — Infisical exports last and can clobber Compose values.
- One unique `OTEL_SERVICE_NAME` per process (API, worker, and web are different services).

## Collector Coolify setup

1. Create a Coolify Docker Compose resource pointing at this repo (`docker-compose.yml`).
2. Set collector env from [`.env.example`](.env.example), at minimum:

   ```bash
   SIGNOZ_OTLP_ENDPOINT=https://otel.roborew.xyz
   SIGNOZ_HOST=otel.roborew.xyz
   SIGNOZ_INGESTION_KEY=
   DEPLOYMENT_ENVIRONMENT=prod-coolify-host-01
   ```

3. Deploy one instance **per Docker host** you want monitored.
4. Confirm health: `http://localhost:13133` on that host (collector health check).

## App project checklist

Use this when wiring any Coolify app on the same host as the collector. Language SDKs / auto-instrumentation are app-repo work; this section covers Docker reachability and env alignment only.

### 1. Reach the host gateway

**Compose apps** — on each instrumented service:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
environment:
  OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT:-http://host.docker.internal:4318}
  OTEL_SERVICE_NAME: your-service-name
  # Do not set OTEL_EXPORTER_OTLP_HEADERS
```

**Coolify Dockerfile apps** (no compose) — add the equivalent host mapping and env in Coolify:

- Custom Docker options: `--add-host=host.docker.internal:host-gateway`
- Env: `OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318` and a unique `OTEL_SERVICE_NAME`

### 2. Instrument the process

After Docker/env are set, enable OpenTelemetry in the app (Python / Node / Ruby / etc.) so it honors `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME`. See [SigNoz instrumentation docs](https://signoz.io/docs/instrumentation/).

### 3. Do not

- Point apps at `https://otel.roborew.xyz` (bypasses the local collector).
- Set `OTEL_EXPORTER_OTLP_HEADERS` / `signoz-ingestion-key` on apps for self-hosted via this collector.
- Use `localhost:4318` from a bridge-networked app container (`localhost` is the container itself).
- Expect Coolify shared-network DNS (`http://signoz-collection-agent:4318`) while this collector uses `network_mode: host`.

### 4. Validate

1. On the host: collector healthy at `http://localhost:13133`.
2. From an app container: `wget -qO- http://host.docker.internal:13133` (or equivalent) succeeds.
3. After instrumentation: collector logs show OTLP traffic; SigNoz shows the new `OTEL_SERVICE_NAME` values under Services / Traces.

## Example: Fidget naming

Illustrative only — apply the checklist in those app repos separately.

| Process | `OTEL_SERVICE_NAME` |
| --- | --- |
| ingest API | `fidget-ingest-api` |
| ingest Celery worker | `fidget-ingest-worker` |
| ingest Celery beat | `fidget-ingest-beat` |
| Next.js web | `fidget-web` |

Skip Valkey, one-shot migrate jobs, and other non-app sidecars unless you intentionally instrument them.

## Ports (collector, host network)

| Port | Purpose |
| --- | --- |
| `4317` | OTLP gRPC receiver |
| `4318` | OTLP HTTP receiver (preferred for apps) |
| `13133` | Health check |
| `1777` | pprof |
| `55679` | zpages |

## Related files

- [`docker-compose.yml`](docker-compose.yml) — Coolify Compose service (`network_mode: host`)
- [`config.yaml`](config.yaml) — receivers, processors, OTLP/HTTP exporter to SigNoz
- [`.env.example`](.env.example) — collector Coolify env template + app OTEL contract reminder
- [`templates/container-metrics-coolify.json`](templates/container-metrics-coolify.json) — SigNoz dashboard for Coolify container metrics
