# Deploy em Produção — Toggle Master (EKS)

## Infraestrutura utilizada

| Recurso | Identificador |
|---|---|
| Cluster EKS | `fiap-clusters` |
| Load Balancer | `fiap-ingress-lb-450359770.us-east-1.elb.amazonaws.com` |
| RDS auth-service | `auth-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com` |
| RDS flag-service | `flag-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com` |
| RDS targeting-service | `targeting-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com` |
| ElastiCache Redis | `evaluation-service-redis.f512fy.ng.0001.use1.cache.amazonaws.com:6379` |
| SQS Queue | `https://sqs.us-east-1.amazonaws.com/244257696167/evaluation-events` |

---

## 1. Credenciais AWS (AWS Academy)

As credenciais são temporárias e expiram ao encerrar o lab.
Obtê-las em: **Vocareum → AWS Details → Show**.

Codificar em base64 e atualizar os secrets do `analytics-service` e `evaluation-service`:

```bash
KEY_ID=$(echo -n "SEU_ACCESS_KEY_ID" | base64 -w0)
SECRET=$(echo -n "SEU_SECRET_ACCESS_KEY" | base64 -w0)
TOKEN=$(echo -n "SEU_SESSION_TOKEN" | base64 -w0)

echo "KEY_ID: $KEY_ID"
echo "SECRET: $SECRET"
echo "TOKEN:  $TOKEN"
```

Editar `k8s/analytics-service/secret.yaml` e `k8s/evaluation-service/secret.yaml` com os valores gerados:

```yaml
data:
  AWS_ACCESS_KEY_ID: "<base64 do KEY_ID>"
  AWS_SECRET_ACCESS_KEY: "<base64 do SECRET>"
  AWS_SESSION_TOKEN: "<base64 do TOKEN>"
```

Aplicar:
```bash
kubectl apply -f k8s/analytics-service/secret.yaml
kubectl apply -f k8s/evaluation-service/secret.yaml

kubectl rollout restart deployment/analytics-service -n analytics-service
kubectl rollout restart deployment/evaluation-service -n evaluation-service
```

> ⚠️ **Atenção:** Isso deve ser repetido a cada nova sessão do AWS Academy, pois as credenciais expiram ao encerrar o lab.

---

## 2. MASTER_KEY do auth-service

A `MASTER_KEY` protege o endpoint de criação de API Keys (`/auth/admin/keys`). Deve ser uma string longa, aleatória e única.

### Gerar e codificar a MASTER_KEY

```bash
MASTER_KEY="$(openssl rand -hex 32)"
MASTER_KEY_B64=$(echo -n "$MASTER_KEY" | base64 -w0)
echo "MASTER_KEY: $MASTER_KEY"
echo "Base64:     $MASTER_KEY_B64"
```

Editar `k8s/auth-service/secret.yaml`:

```yaml
data:
  DATABASE_URL: "<base64 da connection string>"
  MASTER_KEY: "<base64 da MASTER_KEY gerada acima>"
```

Aplicar:

```bash
kubectl apply -f k8s/auth-service/secret.yaml
kubectl rollout restart deployment/auth-service -n auth-service
```

> ⚠️ **Guarde o valor original da MASTER_KEY** — ela será necessária para criar API Keys via `/auth/admin/keys`.

---

## 3. ECR — Repositórios e push das imagens

### Criar os repositórios

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

for SERVICE in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr create-repository \
    --repository-name ${SERVICE} \
    --region ${REGION}
done
```

### Autenticar o Docker no ECR

```bash
aws ecr get-login-password --region ${REGION} \
  | docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
```

### Build e push de cada imagem

> ⚠️ **Importante:** Use `${SERVICE}` com chaves para evitar que o bash concatene o nome da variável com texto adjacente (ex: o bug `analytics-serviceatest`).

```bash
for SERVICE in auth-service flag-service targeting-service evaluation-service analytics-service; do
  docker build -t ${SERVICE} ./${SERVICE}
  docker tag ${SERVICE}:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:latest
  docker push \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:latest
done
```

Após o push, atualize o campo `image` nos `deployment.yaml` de cada serviço:
```
image: 244257696167.dkr.ecr.us-east-1.amazonaws.com/<service>:latest
```

---

## 4. Alterações nos manifestos K8s

### analytics-service/deployment.yaml
Adicionado `envFrom` para injetar as credenciais AWS do secret:

```yaml
envFrom:
  - secretRef:
      name: analytics-service-secret
```

### evaluation-service/deployment.yaml
Adicionado `envFrom` para injetar `SERVICE_API_KEY` e credenciais AWS:

```yaml
envFrom:
  - secretRef:
      name: evaluation-service-secret
```

### evaluation-service/secret.yaml
Adicionados campos AWS além do `SERVICE_API_KEY`:

```yaml
data:
  SERVICE_API_KEY: "<base64>"
  AWS_ACCESS_KEY_ID: "<base64>"
  AWS_SECRET_ACCESS_KEY: "<base64>"
  AWS_SESSION_TOKEN: "<base64>"
```

### ingress.yaml — ExternalName services substituídos por Endpoints manuais

O ingress-nginx não consegue rotear para `ExternalName` services cross-namespace pois eles não possuem ClusterIP. A solução foi substituir por Services com Endpoints manuais apontando diretamente para os ClusterIPs dos serviços.

Para obter os ClusterIPs atuais:
```bash
kubectl get svc -A | grep -E "flag-service |targeting-service |evaluation-service |analytics-service "
```

Substituir no `ingress.yaml` os blocos ExternalName pelo seguinte padrão (repetir para cada serviço):
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: flag-service-ext
  namespace: auth-service
spec:
  ports:
    - port: 8002
---
apiVersion: v1
kind: Endpoints
metadata:
  name: flag-service-ext
  namespace: auth-service
subsets:
  - addresses:
      - ip: <CLUSTER_IP_DO_FLAG_SERVICE>
    ports:
      - port: 8002
```

> ⚠️ **Atenção:** Os ClusterIPs podem mudar se os services forem recriados. Nesse caso, atualize os Endpoints e reaplique o ingress.

---

## 5. Bancos de dados RDS

### Criação das instâncias

```bash
for DB_ID in auth-service-db flag-service-db targeting-service-db; do
  aws rds create-db-instance \
    --db-instance-identifier ${DB_ID} \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username postgres \
    --master-user-password <SENHA_AQUI> \
    --allocated-storage 20 \
    --no-multi-az \
    --publicly-accessible \
    --region us-east-1
done
```

Aguardar todos ficarem `available` (pode demorar 5-10 minutos):

```bash
for DB in auth-service-db flag-service-db targeting-service-db; do
  echo -n "Aguardando $DB... "
  aws rds wait db-instance-available \
    --db-instance-identifier $DB \
    --region us-east-1
  echo "OK"
done
```

### Obter endpoints e gerar connection strings em base64

```bash
for DB in auth-service-db flag-service-db targeting-service-db; do
  ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier $DB \
    --region us-east-1 \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)

  DBNAME=$(echo $DB | sed 's/-service-db/db/')
  CONN="postgres://postgres:<SENHA>@$ENDPOINT:5432/$DBNAME?sslmode=require"
  ENCODED=$(echo -n "$CONN" | base64 -w0)

  echo "=== $DB ==="
  echo "plain:  $CONN"
  echo "base64: $ENCODED"
  echo ""
done
```

> ⚠️ **sslmode=require:** O RDS por padrão exige SSL. Use `sslmode=require` na connection string — `sslmode=disable` causará erro `FATAL: no pg_hba.conf entry`.

### Liberar porta 5432 nos Security Groups

```bash
for DB in auth-service-db flag-service-db targeting-service-db; do
  SG=$(aws rds describe-db-instances \
    --db-instance-identifier $DB \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text --region us-east-1)
  aws ec2 authorize-security-group-ingress \
    --group-id $SG --protocol tcp --port 5432 \
    --cidr 0.0.0.0/0 --region us-east-1
done
```

### Criar bancos e tabelas (migrations manuais)

> ⚠️ **Importante:** O banco `authdb` não existe por padrão — o RDS cria apenas o banco `postgres`. Crie-o antes de criar as tabelas.

```bash
# 1. Criar banco authdb no auth-service-db
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n auth-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h auth-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE DATABASE authdb;"

# 2. Criar tabela api_keys no banco authdb
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n auth-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h auth-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com \
     -U postgres -d authdb \
     -c "CREATE TABLE IF NOT EXISTS api_keys (
       id SERIAL PRIMARY KEY,
       name VARCHAR(255) NOT NULL UNIQUE,
       key_hash VARCHAR(255) NOT NULL UNIQUE,
       description TEXT,
       is_active BOOLEAN DEFAULT TRUE,
       created_at TIMESTAMP DEFAULT NOW()
     );"

# 3. Criar tabela flags no flag-service-db (banco postgres já existe)
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n flag-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h flag-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE TABLE IF NOT EXISTS flags (
       id SERIAL PRIMARY KEY,
       name VARCHAR(255) NOT NULL UNIQUE,
       description TEXT,
       is_enabled BOOLEAN DEFAULT FALSE,
       created_at TIMESTAMP DEFAULT NOW(),
       updated_at TIMESTAMP DEFAULT NOW()
     );"

# 4. Criar tabela targeting_rules no targeting-service-db (banco postgres já existe)
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n targeting-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h targeting-service-db.cbgsrgxwf2wi.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE TABLE IF NOT EXISTS targeting_rules (
       id SERIAL PRIMARY KEY,
       flag_name VARCHAR(255) NOT NULL UNIQUE,
       is_enabled BOOLEAN DEFAULT TRUE,
       rules JSONB NOT NULL,
       created_at TIMESTAMP DEFAULT NOW(),
       updated_at TIMESTAMP DEFAULT NOW()
     );"
```

---

## 6. ElastiCache Redis

### Criar o cluster Redis

```bash
aws elasticache create-replication-group \
  --replication-group-id evaluation-service-redis \
  --replication-group-description "Redis for evaluation-service" \
  --num-cache-clusters 1 \
  --cache-node-type cache.t3.micro \
  --engine redis \
  --region us-east-1
```

Aguardar ficar `available` e obter o endpoint:

> ⚠️ **Atenção:** O Redis é criado como ReplicationGroup, não como CacheCluster simples. Use o comando correto abaixo — `describe-cache-clusters` retornará erro `CacheClusterNotFound`.

```bash
aws elasticache describe-replication-groups \
  --replication-group-id evaluation-service-redis \
  --region us-east-1 \
  --query "ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address" \
  --output text
```

A connection string ficará:
```
redis://<endpoint>:6379
```

### Liberar porta 6379 para o SG do EKS

```bash
# Pega o SG default da VPC (usado pelo Redis quando criado sem SG explícito)
DEFAULT_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=default" \
             "Name=vpc-id,Values=vpc-05da6afadff5c6e2c" \
  --region us-east-1 \
  --query "SecurityGroups[0].GroupId" \
  --output text)

echo "SG default: $DEFAULT_SG"

# Libera porta 6379 para o SG dos nodes do EKS
aws ec2 authorize-security-group-ingress \
  --group-id $DEFAULT_SG \
  --protocol tcp \
  --port 6379 \
  --source-group sg-09650fb07146451df \
  --region us-east-1
```

> Se retornar `InvalidPermission.Duplicate`, a regra já existe — está tudo certo.

---

## 7. DynamoDB — Tabela de eventos de analytics

O `analytics-service` consome eventos da fila SQS e os persiste na tabela `analytics-events` do DynamoDB.

### Criar a tabela

```bash
aws dynamodb create-table \
  --table-name analytics-events \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Aguardar a tabela ficar `ACTIVE`:

```bash
aws dynamodb wait table-exists \
  --table-name analytics-events \
  --region us-east-1
```

### Estrutura dos itens gravados

| Atributo | Tipo | Descrição |
|---|---|---|
| `event_id` | String (PK) | UUID gerado pelo analytics-service |
| `user_id` | String | ID do usuário avaliado |
| `flag_name` | String | Nome da feature flag |
| `result` | Boolean | Resultado da avaliação |
| `timestamp` | String | Timestamp do evento |

---

## 8. SQS — Fila de eventos de avaliação

O `evaluation-service` publica eventos na fila e o `analytics-service` os consome via long-polling.

### Criar a fila

```bash
aws sqs create-queue \
  --queue-name evaluation-events \
  --attributes ReceiveMessageWaitTimeSeconds=20,VisibilityTimeout=60 \
  --region us-east-1
```

> `ReceiveMessageWaitTimeSeconds=20` habilita long-polling, que é o modo usado pelo `analytics-service`.

### Obter a URL da fila

```bash
aws sqs get-queue-url \
  --queue-name evaluation-events \
  --region us-east-1 \
  --query 'QueueUrl' \
  --output text
```

Atualizar `k8s/evaluation-service/configmap.yaml` e `k8s/analytics-service/configmap.yaml` com a URL retornada:

```yaml
AWS_SQS_URL: "https://sqs.us-east-1.amazonaws.com/<ACCOUNT_ID>/evaluation-events"
```

---

## 9. Ingress-nginx Controller

O ingress-nginx precisa ser instalado antes de criar o ALB, pois o Load Balancer encaminha tráfego para o NodePort `32308` exposto pelo controller.

### Instalar via Helm

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=32308
```

### Verificar a instalação

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

> O `EXTERNAL-IP` do serviço ficará `<pending>` — isso é esperado. O tráfego chegará via ALB → NodePort `32308`.

---

## 10. Load Balancer (criação manual)

O EKS não conseguiu provisionar o LB automaticamente no AWS Academy devido a restrições de IAM (`iam:AttachRolePolicy` bloqueado). Solução adotada: criar um Application Load Balancer manualmente apontando para o NodePort do ingress-nginx.

### Como seria o processo correto (fora do AWS Academy)

Em um ambiente sem restrições de IAM, o correto é usar o **AWS Load Balancer Controller**:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=fiap-clusters \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::244257696167:role/AmazonEKSLoadBalancerControllerRole
```

Com o Ingress anotado:
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

O ALB seria provisionado automaticamente e o `EXTERNAL-IP` do ingress preenchido.

---

### Solução adotada no AWS Academy: ALB manual

#### Passo 1 — Descobrir os IDs necessários

```bash
# Subnets do cluster EKS
aws eks describe-cluster \
  --name fiap-clusters \
  --query 'cluster.resourcesVpcConfig.subnetIds' \
  --output table --region us-east-1

# VPC ID do cluster
aws eks describe-cluster \
  --name fiap-clusters \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text --region us-east-1

# Security Group dos nodes
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' \
  --output table --region us-east-1

# AZ de cada node (crucial para escolher subnets do ALB)
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/fiap-clusters,Values=owned" \
  --region us-east-1 \
  --query "Reservations[*].Instances[*].{ID:InstanceId,AZ:Placement.AvailabilityZone,Subnet:SubnetId}" \
  --output table
```

#### Passo 2 — Taguear as subnets

> ⚠️ **Importante:** Use array bash com `"${SUBNETS[@]}"` para iterar corretamente — passar a string inteira como argumento único causará erro `InvalidID`.

```bash
CLUSTER="fiap-clusters"
SUBNETS=(
  "subnet-04ab10693fea1bdcf"
  "subnet-0b34ff5331892a52a"
  "subnet-081d478c2c8a3a908"
  "subnet-00d58a3dbeab35fb8"
  "subnet-05043c6603a41a4a1"
)

for subnet in "${SUBNETS[@]}"; do
  echo "Tagueando $subnet..."
  aws ec2 create-tags --resources "$subnet" \
    --tags \
      Key=kubernetes.io/cluster/$CLUSTER,Value=shared \
      Key=kubernetes.io/role/elb,Value=1 \
    --region us-east-1
done
```

#### Passo 3 — Criar ALB, Target Group e Listener

> ⚠️ **Importante:** O ALB precisa ter subnets nas mesmas AZs dos nodes. Nodes em AZs não cobertas ficam com status `unused` e o ALB retorna 502/503.

```bash
NODE_SG="sg-09650fb07146451df"
VPC_ID="vpc-05da6afadff5c6e2c"

# Criar o ALB (inclua subnets das AZs onde os nodes estão)
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name fiap-ingress-lb \
  --type application \
  --scheme internet-facing \
  --subnets subnet-04ab10693fea1bdcf subnet-0b34ff5331892a52a subnet-05043c6603a41a4a1 \
  --security-groups ${NODE_SG} \
  --region us-east-1 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB ARN: $ALB_ARN"

# Criar Target Group apontando para o NodePort do ingress-nginx (32308)
TG_ARN=$(aws elbv2 create-target-group \
  --name fiap-ingress-tg \
  --protocol HTTP \
  --port 32308 \
  --vpc-id ${VPC_ID} \
  --target-type instance \
  --region us-east-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "TG ARN: $TG_ARN"

# Registrar os nodes automaticamente
NODE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/fiap-clusters,Values=owned" \
  --region us-east-1 \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

TARGETS=$(echo $NODE_IDS | tr ' ' '\n' | sed 's/.*/Id=&/')

aws elbv2 register-targets \
  --target-group-arn ${TG_ARN} \
  --targets ${TARGETS} \
  --region us-east-1

# Criar Listener na porta 80
aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --region us-east-1

# Liberar portas no SG dos nodes
aws ec2 authorize-security-group-ingress \
  --group-id ${NODE_SG} --protocol tcp --port 80 --cidr 0.0.0.0/0 --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id ${NODE_SG} --protocol tcp --port 32308 --cidr 0.0.0.0/0 --region us-east-1

# Obter o DNS do ALB
BASE_URL=$(aws elbv2 describe-load-balancers \
  --names fiap-ingress-lb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1)

echo "Base URL: http://$BASE_URL"
```

> ⚠️ **Atenção:** Ao recriar o ALB, o DNS muda. Sempre obtenha o DNS atual com o comando acima. O Listener e o Target Group também precisam ser recriados quando o ALB é deletado.

---

## 11. Configurar SERVICE_API_KEY no evaluation-service

O `evaluation-service` precisa de uma API Key válida para se autenticar no `flag-service` e `targeting-service`. Sem ela, todas as avaliações retornam `401` e o endpoint `/evaluate` falha com `"Erro interno ao avaliar a flag"`.

```bash
BASE="http://$(aws elbv2 describe-load-balancers \
  --names fiap-ingress-lb \
  --query 'LoadBalancers[0].DNSName' \
  --output text --region us-east-1)"

MASTER_KEY=$(kubectl get secret auth-service-secret -n auth-service \
  -o jsonpath='{.data.MASTER_KEY}' | base64 -d)

echo "BASE: $BASE"
echo "MASTER_KEY: $MASTER_KEY"

# Criar API key
API_KEY=$(curl -s -X POST $BASE/auth/admin/keys \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "evaluation-service-key"}' | jq -r '.key')

echo "API_KEY: $API_KEY"

# Atualizar o secret do evaluation-service
API_KEY_B64=$(echo -n "$API_KEY" | base64 -w0)
kubectl patch secret evaluation-service-secret -n evaluation-service \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/SERVICE_API_KEY\", \"value\": \"$API_KEY_B64\"}]"

kubectl rollout restart deployment/evaluation-service -n evaluation-service
kubectl rollout status deployment/evaluation-service -n evaluation-service
```

---

## 12. Criar flag e regra de teste

Antes de rodar os testes, crie a flag e a regra de targeting:

```bash
BASE="http://fiap-ingress-lb-450359770.us-east-1.elb.amazonaws.com"
API_KEY="<sua-api-key>"

# Criar a flag
curl -s -X POST $BASE/flags/flags \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "test-flag", "description": "flag de teste", "is_enabled": true}'

# Criar a regra de targeting
curl -s -X POST $BASE/targeting/rules \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "test-flag", "is_enabled": true, "rules": {"type": "PERCENTAGE", "value": 50}}'
```

> ⚠️ **Formato correto da Targeting Rule:** `{"type": "PERCENTAGE", "value": 50}` — **não** usar `{"PERCENTAGE": 50}`.

---

## 13. Endpoints disponíveis

Base URL: `http://fiap-ingress-lb-450359770.us-east-1.elb.amazonaws.com`

| Serviço | Método | Endpoint | Auth |
|---|---|---|---|
| auth | GET | `/auth/health` | nenhuma |
| auth | POST | `/auth/admin/keys` | MASTER_KEY |
| auth | GET | `/auth/validate` | API_KEY |
| flags | GET | `/flags/health` | nenhuma |
| flags | GET/POST | `/flags/flags` | API_KEY |
| flags | GET/PUT/DELETE | `/flags/flags/<n>` | API_KEY |
| targeting | GET | `/targeting/health` | nenhuma |
| targeting | POST | `/targeting/rules` | API_KEY |
| targeting | GET/PUT/DELETE | `/targeting/rules/<flag_name>` | API_KEY |
| evaluation | GET | `/evaluate/health` | nenhuma |
| evaluation | GET | `/evaluate/evaluate?flag_name=X&user_id=Y` | nenhuma |
| analytics | GET | `/analytics/health` | nenhuma |

---

## 14. Problemas encontrados e soluções

| Problema | Causa | Solução |
|---|---|---|
| `CrashLoopBackOff` no auth-service | `sslmode=disable` — RDS exige SSL | Trocar para `sslmode=require` na connection string |
| `database "authdb" does not exist` | RDS cria apenas o banco `postgres` por padrão | Criar o banco `authdb` manualmente via psql-client antes de criar a tabela |
| `relation "targeting_rules" does not exist` | Migration não rodada no namespace e banco corretos | Criar a tabela no namespace `targeting-service` apontando para o banco correto |
| `503 Service Temporarily Unavailable` | ExternalName services não têm ClusterIP — ingress-nginx não consegue rotear | Substituir ExternalName por Services + Endpoints manuais com ClusterIPs |
| `Target.NotInUse` no Target Group | Nodes em AZs não cobertas pelo ALB | Verificar AZs dos nodes e recriar ALB com subnets correspondentes |
| `evaluation-service` retornando `401` | `SERVICE_API_KEY` vazia no secret | Criar API Key via auth-service e atualizar o secret via `kubectl patch` |
| `analytics-serviceatest` no docker tag | `$SERVICE` sem chaves concatenou com texto adjacente | Usar `${SERVICE}` com chaves em todos os comandos do loop |
| DNS do ALB não resolve | ALB recriado gera novo DNS | Sempre obter o DNS atual via `aws elbv2 describe-load-balancers` |
| `CacheClusterNotFound` no ElastiCache | Redis criado como ReplicationGroup, não CacheCluster | Usar `describe-replication-groups` em vez de `describe-cache-clusters` |

---

## 15. Observações importantes (AWS Academy)

- **Credenciais AWS expiram** ao encerrar o lab — repetir o passo 1 a cada nova sessão
- O `EXTERNAL-IP` do ingress-nginx ficará `<pending>` — usar o ALB manual criado no passo 10
- Não é possível criar novas IAM roles (`iam:AttachRolePolicy` bloqueado) — por isso o AWS Load Balancer Controller não funciona
- A `LabRole` já possui permissões suficientes para EKS, RDS, ElastiCache, SQS e DynamoDB
- ClusterIPs dos services podem mudar se forem recriados — atualizar os Endpoints no `ingress.yaml` nesse caso
- Ao recriar o ALB, o Listener e o Target Group também precisam ser recriados manualmente
