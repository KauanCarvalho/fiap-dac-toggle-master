# Fase 4 — Instrumentação, APM e Self-Healing

A stack de monitoramento em si (Prometheus, Loki, Grafana, OTel Collector, Datadog Agent) foi provisionada no repositório de GitOps ([fiap-dac-toggle-master-gitops](https://github.com/KauanCarvalho/fiap-dac-toggle-master-gitops)); este repositório concentra a **instrumentação do código das aplicações** e a **automação de self-healing**.

---

## 1. Instrumentação com OpenTelemetry

Os 5 microsserviços passaram a exportar traces via OTLP gRPC para o OTel Collector do cluster (`otel-collector.monitoring.svc.cluster.local:4317`), permitindo distributed tracing e Service Map no APM.

| Serviço | Linguagem | Método | Onde |
| :--- | :--- | :--- | :--- |
| **Auth Service** | Go | SDK manual do OTel — `TracerProvider`, exporter `otlptracegrpc`, propagador `TraceContext + Baggage` | `local/services/auth-service/otel.go` |
| **Evaluation Service** | Go | Mesma abordagem manual do Auth Service | `local/services/evaluation-service/otel.go` |
| **Flag Service** | Python | Auto-instrumentação: `opentelemetry-bootstrap -a install` no build da imagem, entrypoint trocado para `opentelemetry-instrument gunicorn ...` | `local/services/flag-service/Dockerfile` |
| **Targeting Service** | Python | Mesma auto-instrumentação via Dockerfile | `local/services/targeting-service/Dockerfile` |
| **Analytics Service** | Python | Mesma auto-instrumentação via Dockerfile | `local/services/analytics-service/Dockerfile` |

O endpoint OTLP é configurável via variável de ambiente `OTEL_EXPORTER_OTLP_ENDPOINT`, com fallback para o endereço interno do cluster caso não seja definida.

---

## 2. Self-Healing (Runbook Automation)

Workflow [`.github/workflows/self-healing.yml`](.github/workflows/self-healing.yml) — mitiga falhas sem intervenção humana.

**Disparo:**
- `repository_dispatch` (tipo `alert-firing`), esperado a partir de um webhook do AlertManager.
- `workflow_dispatch` manual, escolhendo o serviço e o namespace a reiniciar (usado hoje para validação).

**Ação corretiva:**
```bash
kubectl rollout restart deployment/<service> -n <namespace>
kubectl rollout status deployment/<service> -n <namespace> --timeout=120s
```

**Feedback:** notificação no Discord (sucesso ou falha), com link direto para a execução no GitHub Actions.

> **Pendência conhecida**: o disparo automático via `repository_dispatch` ainda não está conectado ao AlertManager — falta uma ponte (ex.: Lambda com Function URL recebendo o webhook do AlertManager e chamando `POST /repos/.../dispatches`). Até essa ponte existir, o self-healing é validado via `workflow_dispatch` manual, não pelo alerta real.

---

## 3. Onde encontrar o restante da Fase 4

| Item | Repositório | Localização |
| :--- | :--- | :--- |
| Prometheus / Loki / Grafana | gitops | `terraform/production/monitoring.tf` |
| OTel Collector (DaemonSet + pipelines) | gitops | `terraform/production/monitoring.tf` |
| Datadog Agent | gitops | `terraform/production/monitoring.tf` |
| Dashboard customizado do Grafana | gitops | `k8s/apps/monitoring/grafana-dashboard.yaml` |
| Regras de Alerta (PrometheusRule) | gitops | `k8s/apps/monitoring/alert-rules.yaml` |
| Integração PagerDuty / Discord | gitops | `terraform/production/monitoring.tf` (AlertManager config) |
