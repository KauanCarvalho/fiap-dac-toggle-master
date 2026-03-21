# Checklist pré-deploy

## Imagens ECR

Substitua os placeholders em todos os `deployment.yaml` antes de aplicar.

> [!TIP]
> Comando para substituir em lote o ID da conta e região em todos os manifestos de deploy (Executar da raiz do projeto):
> ```bash
> find k8s -name "deployment.yaml" | xargs sed -i '' 's/<ACCOUNT_ID>/123456789012/g; s/<AWS_REGION>/us-east-1/g'
> ```

| Arquivo | Placeholder | O que colocar |
|---|---|---|
| [`k8s/auth-service/deployment.yaml`](../../k8s/auth-service/deployment.yaml) | `<ACCOUNT_ID>` / `<AWS_REGION>` | ID da conta AWS (12 dígitos) e região |
| [`k8s/flag-service/deployment.yaml`](../../k8s/flag-service/deployment.yaml) | `<ACCOUNT_ID>` / `<AWS_REGION>` | idem |
| [`k8s/targeting-service/deployment.yaml`](../../k8s/targeting-service/deployment.yaml) | `<ACCOUNT_ID>` / `<AWS_REGION>` | idem |
| [`k8s/analytics-service/deployment.yaml`](../../k8s/analytics-service/deployment.yaml) | `<ACCOUNT_ID>` / `<AWS_REGION>` | idem |
| [`k8s/evaluation-service/deployment.yaml`](../../k8s/evaluation-service/deployment.yaml) | `<ACCOUNT_ID>` / `<AWS_REGION>` | idem |

> [!IMPORTANT]
> Em produção, evite a tag `latest`. Prefira tags imutáveis como `v1.0.0` ou o SHA do commit para garantir rastreabilidade.

---

## Secrets — valores base64 reais

Todos os valores em `secret.yaml` são placeholders e **devem ser substituídos** por valores reais codificados em base64.

> [!NOTE]
> Para gerar um valor em base64 via terminal:
> ```bash
> echo -n "seu-valor-real" | base64
> ```

| Arquivo | Chave | Como gerar |
|---|---|---|
| [`k8s/auth-service/secret.yaml`](../../k8s/auth-service/secret.yaml) | `DATABASE_URL` | `echo -n "postgres://user:pass@auth-db:5432/authdb?sslmode=disable" | base64` |
| [`k8s/auth-service/secret.yaml`](../../k8s/auth-service/secret.yaml) | `MASTER_KEY` | `echo -n "sua-master-key-real" | base64` |
| [`k8s/flag-service/secret.yaml`](../../k8s/flag-service/secret.yaml) | `DATABASE_URL` | `echo -n "postgres://user:pass@toggle-db:5432/toggledb?sslmode=disable" | base64` |
| [`k8s/targeting-service/secret.yaml`](../../k8s/targeting-service/secret.yaml) | `DATABASE_URL` | Mesmo toggle-db do flag-service |
| [`k8s/analytics-service/secret.yaml`](../../k8s/analytics-service/secret.yaml) | `AWS_ACCESS_KEY_ID` | `echo -n "AKIA..." | base64` |
| [`k8s/analytics-service/secret.yaml`](../../k8s/analytics-service/secret.yaml) | `AWS_SECRET_ACCESS_KEY` | `echo -n "wJalr..." | base64` |
| [`k8s/evaluation-service/secret.yaml`](../../k8s/evaluation-service/secret.yaml) | `SERVICE_API_KEY` | `echo -n "sua-api-key" | base64` |
| [`k8s/evaluation-service/secret.yaml`](../../k8s/evaluation-service/secret.yaml) | `AWS_ACCESS_KEY_ID` | `echo -n "AKIA..." | base64` |
| [`k8s/evaluation-service/secret.yaml`](../../k8s/evaluation-service/secret.yaml) | `AWS_SECRET_ACCESS_KEY` | `echo -n "wJalr..." | base64` |

---

## ConfigMaps — valores que precisam ser ajustados

| Arquivo | Chave | O que verificar |
|---|---|---|
| [`k8s/analytics-service/configmap.yaml`](../../k8s/analytics-service/configmap.yaml) | `AWS_SQS_URL` | Substituir `<ACCOUNT_ID>` pelo ID real da conta |
| [`k8s/analytics-service/configmap.yaml`](../../k8s/analytics-service/configmap.yaml) | `AWS_ENDPOINT_URL` | Deixar **vazio** em produção |
| [`k8s/evaluation-service/configmap.yaml`](../../k8s/evaluation-service/configmap.yaml) | `AWS_SQS_URL` | Substituir `<ACCOUNT_ID>` pelo ID real da conta |
| [`k8s/evaluation-service/configmap.yaml`](../../k8s/evaluation-service/configmap.yaml) | `AWS_ENDPOINT_URL` | Deixar **vazio** em produção |
| [`k8s/evaluation-service/configmap.yaml`](../../k8s/evaluation-service/configmap.yaml) | `REDIS_URL` | Confirmar endpoint do ElastiCache |

---

## Infraestrutura do cluster

- [ ] **metrics-server** instalado — obrigatório para o HPA (CPU)
- [ ] **NGINX Ingress Controller** instalado — obrigatório para o [ingress.yaml](../../k8s/ingress.yaml)
- [ ] Banco de dados **auth-db** acessível dentro do cluster
- [ ] Banco de dados **toggle-db** acessível dentro do cluster
- [ ] **Redis** acessível dentro do cluster

---

## AWS

- [ ] **ECR login** realizado antes do push:
  ```bash
  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
  ```
- [ ] Imagens enviadas para o ECR com a tag correta
- [ ] Fila **SQS** `evaluation-events` criada
- [ ] Tabela **DynamoDB** `toggle-analytics` criada (`event_id` como partition key)
- [ ] **Permissões IAM** configuradas para SQS e DynamoDB

---

## Deploy com Kustomize

> [!NOTE]
> Execute os comandos a seguir a partir da raiz do projeto.

```bash
# Aplicação total (Namespace, Deployments, Services, Ingress)
kubectl apply -k k8s/

# Deploy individual (exemplo)
kubectl apply -k k8s/auth-service/

# Validar manifesto gerado
kubectl kustomize k8s/

# Verificação do status
kubectl get all,hpa,ingress -n toggle-master
```
