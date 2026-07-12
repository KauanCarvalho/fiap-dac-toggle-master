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

---

## 4. Runbook: como testar um trace distribuído ponta a ponta

Este passo a passo existe porque, ao validar o tracing em produção, descobrimos que os bancos do EKS (RDS) nunca tinham recebido o schema (`init.sql`) das aplicações — só o `docker-compose.local.yml` roda essas migrations automaticamente. Sem isso, `auth-service`, `flag-service` e `targeting-service` respondem 401/500 para qualquer chamada. Os passos abaixo já foram executados uma vez em produção (7/2026); documentamos aqui para caso um novo ambiente precise do mesmo tratamento, ou para o time entender por que essas tabelas existem sem uma migration formal no pipeline.

### 4.1 Aplicar o schema no banco (se ainda não existir)

Sintoma: logs do `auth-service`/`flag-service`/`targeting-service` mostrando `ERROR: relation "..." does not exist (SQLSTATE 42P01)`.

Cada serviço já tem o SQL certo em `local/services/<service>/db/init.sql` (é o mesmo script que o Postgres local roda automaticamente). Para aplicar numa RDS de produção, sem migration tool formal, subimos um pod temporário com `psql` na mesma namespace do serviço e rodamos o arquivo via stdin:

```bash
# 1. Pegar a DATABASE_URL do serviço (host, usuário, senha, db já resolvidos)
kubectl get secret -n <namespace> <service>-secret -o jsonpath='{.data.DATABASE_URL}' | base64 -d
# ex: postgres://postgres:Auth123!@auth-service-db.xxxx.us-east-1.rds.amazonaws.com:5432/auth_db

# 2. Subir um pod com psql na mesma namespace (extraia host/senha/db da URL acima)
kubectl run psql-migrate -n <namespace> --image=postgres:16-alpine \
  --env="PGPASSWORD=<senha>" --restart=Never --command -- sleep 3600
kubectl wait -n <namespace> --for=condition=Ready pod/psql-migrate --timeout=90s

# 3. Rodar o init.sql do serviço via stdin
kubectl exec -i -n <namespace> psql-migrate -- \
  psql -h <host-rds> -U postgres -d <database> < local/services/<service>/db/init.sql

# 4. Derrubar o pod temporário
kubectl delete pod -n <namespace> psql-migrate --force --grace-period=0
```

Repita para as 3 namespaces que têm banco próprio: `auth-service` (tabela `api_keys`, já vem com uma seed key), `flag-service` (tabela `flags`) e `targeting-service` (tabela `targeting_rules`). Os `CREATE TABLE IF NOT EXISTS` são idempotentes — rodar de novo não quebra nada.

### 4.2 De onde vem a MASTER_KEY e como criar uma API Key nova

O `auth-service` usa duas chaves diferentes:

- **`MASTER_KEY`**: definida como secret (`auth-service-secret`, chave `MASTER_KEY`), injetada via env var. Protege o endpoint `/admin/keys`, que é o único jeito de gerar novas API Keys. Não é "criada" por um processo — é um valor fixo provisionado no Terraform/External Secrets do GitOps, igual a qualquer outro secret do projeto.
- **API Keys de serviço** (ex.: `SERVICE_API_KEY` usada pelo `evaluation-service` para chamar `flag-service`/`targeting-service`): ficam na tabela `api_keys` (hash SHA-256, nunca em texto puro) e são validadas pelo `auth-service` no endpoint público `/validate`. A seed key `local-evaluation-service-seed-key` já vem inserida pelo `init.sql` do `auth-service` e corresponde ao valor `eval_api_key` (o mesmo valor já configurado no secret do `evaluation-service`).

Para pegar a `MASTER_KEY` e gerar uma API Key nova (se precisar de uma diferente da seed):

```bash
# Pegar a MASTER_KEY
kubectl get secret -n auth-service auth-service-secret -o jsonpath='{.data.MASTER_KEY}' | base64 -d

# Criar uma nova API Key (a chave em texto puro só aparece nesta resposta, uma única vez)
curl -X POST "<URL_PUBLICA>/auth/admin/keys" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name":"minha-chave-de-teste"}'
```

### 4.3 Como pegar a URL pública para testar

O tráfego externo entra pelo `ingress-nginx`, exposto via um LoadBalancer da AWS (ELB clássico, sem domínio customizado configurado ainda). Para descobrir a URL atual:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide
# Coluna EXTERNAL-IP: algo como aa4f6d6b1bc6b4702ae5864948bfcdd8-569522669.us-east-1.elb.amazonaws.com
```

> Esse hostname muda se o LoadBalancer for recriado (ex.: `terraform destroy`/`apply` do ingress-nginx). Sempre confira antes de reusar uma URL antiga.

O Ingress expõe os serviços nos seguintes prefixos (ver `k8s/apps/ingress.yaml` no repo gitops):

| Prefixo | Backend | Observação |
| :--- | :--- | :--- |
| `/auth/...` | auth-service | prefixo é removido antes de chegar no backend (rotas reais: `/health`, `/validate`, `/admin/keys`) |
| `/targeting/...` | targeting-service | prefixo é removido (rotas reais: `/rules`, `/rules/<nome>`) |
| `/flags/...` | flag-service | prefixo **não** é removido (rotas reais já incluem `/flags`) |
| `/evaluate` | evaluation-service | prefixo **não** é removido (rota real é exatamente `/evaluate`) |
| `/analytics/...` | analytics-service | só expõe `/health`; o serviço não tem API HTTP própria (consome SQS) |

### 4.4 Criar uma flag + regra de teste e gerar um trace distribuído

Substitua `<URL_PUBLICA>` pelo hostname do passo 4.3 e `<API_KEY>` pela seed key `eval_api_key` (ou pela sua própria, do passo 4.2).

```bash
URL="<URL_PUBLICA>"
KEY="eval_api_key"

# 1. Criar a flag
curl -X POST "$URL/flags" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"name":"minha-flag-teste","description":"flag de teste","is_enabled":true}'

# 2. Criar a regra de segmentação (100% dos usuários = sempre true)
curl -X POST "$URL/targeting/rules" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"flag_name":"minha-flag-teste","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'

# 3. Disparar a avaliação — essa chamada gera um trace atravessando
#    evaluation-service -> flag-service -> auth-service
#                        -> targeting-service -> auth-service
curl "$URL/evaluate?user_id=qualquer-usuario&flag_name=minha-flag-teste"
```

Exemplo real usado na validação (já criado em produção, pode reusar sem precisar dos passos 1 e 2):

```bash
curl "http://aa4f6d6b1bc6b4702ae5864948bfcdd8-569522669.us-east-1.elb.amazonaws.com/evaluate?user_id=teste&flag_name=trace-validation-flag-teste"
```

No Datadog APM, procure em **Traces** por `service:evaluation-service resource_name:"GET /evaluate"`, ordenado pelo mais recente. O trace deve mostrar spans de `evaluation-service`, `flag-service`, `targeting-service` e `auth-service` (2x, uma validação para cada serviço chamador) — essa é a evidência de **Distributed Tracing** e **Service Map** pedida no Tech Challenge.

> Se `flag_name` não existir no banco, `flag-service`/`targeting-service` respondem 404 normalmente (não é bug) — sempre crie a flag/regra antes de testar um nome novo.
