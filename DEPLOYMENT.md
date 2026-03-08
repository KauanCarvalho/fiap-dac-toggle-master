# Deploy em Produção — Toggle Master (EKS)

## Infraestrutura utilizada

| Recurso | Identificador |
|---|---|
| Cluster EKS | `fiap-clusters` |
| Load Balancer | `fiap-ingress-lb-932060456.us-east-1.elb.amazonaws.com` |
| RDS auth-service | `auth-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com` |
| RDS flag-service | `flag-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com` |
| RDS targeting-service | `targeting-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com` |
| ElastiCache Redis | `evaluation-service-redis.alxemv.0001.use1.cache.amazonaws.com:6379` |
| SQS Queue | `https://sqs.us-east-1.amazonaws.com/474171319437/evaluation-events` |

---

## 1. Credenciais AWS (AWS Academy)

As credenciais são temporárias e expiram ao encerrar o lab.
Obtê-las em: **Vocareum → AWS Details → Show**.

Codificar em base64 e atualizar os secrets do `analytics-service` e `evaluation-service`:

```bash
KEY_ID=$(echo -n "SEU_ACCESS_KEY_ID" | base64 -w0)
SECRET=$(echo -n "SEU_SECRET_ACCESS_KEY" | base64 -w0)
TOKEN=$(echo -n "SEU_SESSION_TOKEN" | base64 -w0)
```

Editar `k8s/analytics-service/secret.yaml` e `k8s/evaluation-service/secret.yaml`:

```yaml
data:
  AWS_ACCESS_KEY_ID: "<base64>"
  AWS_SECRET_ACCESS_KEY: "<base64>"
  AWS_SESSION_TOKEN: "<base64>"
```

Aplicar:
```bash
kubectl apply -f k8s/analytics-service/secret.yaml
kubectl apply -f k8s/evaluation-service/secret.yaml
```

---

## 2. MASTER_KEY do auth-service

A `MASTER_KEY` é uma chave secreta definida manualmente que protege o endpoint de criação de API Keys (`/auth/admin/keys`). Deve ser uma string longa, aleatória e única.

### Gerar a MASTER_KEY

```bash
# Opção 1: openssl (recomendado)
openssl rand -hex 32

# Opção 2: /dev/urandom
cat /dev/urandom | tr -dc 'A-F0-9' | head -c 64
```

Exemplo de saída: `045551C9B96D249AB0E993F4749B657`

### Codificar em base64 e atualizar o secret

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

> Guarde o valor original da MASTER_KEY — ela será necessária para criar API Keys via `/auth/admin/keys`.

---

## 3. Alterações nos manifestos K8s

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

---

## 3. Bancos de dados RDS

### Criação das instâncias

```bash
# auth-service
aws rds create-db-instance \
  --db-instance-identifier auth-service-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password <SENHA_AQUI> \
  --allocated-storage 20 \
  --no-multi-az \
  --publicly-accessible \
  --region us-east-1

# flag-service
aws rds create-db-instance \
  --db-instance-identifier flag-service-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password <SENHA_AQUI> \
  --allocated-storage 20 \
  --no-multi-az \
  --publicly-accessible \
  --region us-east-1

# targeting-service
aws rds create-db-instance \
  --db-instance-identifier targeting-service-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password <SENHA_AQUI> \
  --allocated-storage 20 \
  --no-multi-az \
  --publicly-accessible \
  --region us-east-1
```

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

### Criar tabelas (migrations manuais)

```bash
# api_keys (auth-service)
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n auth-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h auth-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE TABLE IF NOT EXISTS api_keys (
       id SERIAL PRIMARY KEY,
       name VARCHAR(255) NOT NULL UNIQUE,
       key_hash VARCHAR(255) NOT NULL UNIQUE,
       description TEXT,
       is_active BOOLEAN DEFAULT TRUE,
       created_at TIMESTAMP DEFAULT NOW()
     );"

# flags (flag-service)
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n flag-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h flag-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE TABLE IF NOT EXISTS flags (
       id SERIAL PRIMARY KEY,
       name VARCHAR(255) NOT NULL UNIQUE,
       description TEXT,
       is_enabled BOOLEAN DEFAULT FALSE,
       created_at TIMESTAMP DEFAULT NOW(),
       updated_at TIMESTAMP DEFAULT NOW()
     );"

# targeting_rules (targeting-service)
kubectl run psql-client --image=postgres:15 --rm -it --restart=Never -n targeting-service \
  --env='PGPASSWORD=<SENHA_AQUI>' \
  -- psql -h targeting-service-db.cxwa80mg64h4.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "CREATE TABLE IF NOT EXISTS targeting_rules (
       id SERIAL PRIMARY KEY,
       flag_name VARCHAR(255) NOT NULL UNIQUE,
       is_enabled BOOLEAN DEFAULT TRUE,
       rules JSONB,
       created_at TIMESTAMP DEFAULT NOW(),
       updated_at TIMESTAMP DEFAULT NOW()
     );"
```

---

## 4. ElastiCache Redis

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

```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id evaluation-service-redis \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text --region us-east-1
```

### Liberar porta 6379:

```bash
SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=vpc-0218e857ac8dc68d7" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' \
  --output text --region us-east-1)

aws ec2 authorize-security-group-ingress \
  --group-id $SG --protocol tcp --port 6379 \
  --cidr 0.0.0.0/0 --region us-east-1
```

---

## 5. Load Balancer (criação manual)

O EKS não conseguiu provisionar o LB automaticamente no AWS Academy devido a restrições de IAM (`iam:AttachRolePolicy` bloqueado). Solução adotada: criar um Classic Load Balancer manualmente.

### Como seria o processo correto (fora do AWS Academy)

Em um ambiente sem restrições de IAM, o correto é usar o **AWS Load Balancer Controller** que provisiona um Application Load Balancer (ALB) automaticamente a partir de anotações no Ingress.

**1. Instalar o AWS Load Balancer Controller via Helm:**

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=fiap-clusters \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::474171319437:role/AmazonEKSLoadBalancerControllerRole
```

**2. Anotar o Ingress para usar ALB:**

```yaml
# k8s/ingress.yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

**3. O ALB seria provisionado automaticamente:**

```bash
kubectl get ingress -A
# EXTERNAL-IP seria preenchido automaticamente com o DNS do ALB
```

---

### Solução adotada no AWS Academy: Classic Load Balancer manual

### Tags nas subnets (necessário para EKS)

```bash
CLUSTER="fiap-clusters"
SUBNETS="subnet-0fae396ae957a7af4 subnet-00249390623fad2c6 subnet-0f410504754070084 subnet-0b67ac8dfff349166 subnet-002c6b0620731b20e"

for subnet in $SUBNETS; do
  aws ec2 create-tags --resources $subnet \
    --tags \
      Key=kubernetes.io/cluster/$CLUSTER,Value=shared \
      Key=kubernetes.io/role/elb,Value=1 \
    --region us-east-1
done
```

### Criar o CLB apontando para o NodePort do ingress-nginx (32308)

```bash
NODE_SG="sg-0b2a47f746b7fd2de"

aws elb create-load-balancer \
  --load-balancer-name fiap-ingress-lb \
  --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=32308" \
  --subnets subnet-0fae396ae957a7af4 subnet-00249390623fad2c6 subnet-0f410504754070084 \
  --security-groups $NODE_SG \
  --region us-east-1

# Registrar os nodes
for INSTANCE in i-0eaedbcf5f202cc65 i-0e1289f99316458c3; do
  aws elb register-instances-with-load-balancer \
    --load-balancer-name fiap-ingress-lb \
    --instances $INSTANCE \
    --region us-east-1
done

# Liberar portas no SG dos nodes
aws ec2 authorize-security-group-ingress \
  --group-id $NODE_SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id $NODE_SG --protocol tcp --port 32308 --cidr 0.0.0.0/0 --region us-east-1
```

---

## 6. Configurar SERVICE_API_KEY no evaluation-service

Após criar a primeira API key via auth-service, configurar no secret do evaluation-service:

```bash
MASTER_KEY=""
BASE="http://fiap-ingress-lb-932060456.us-east-1.elb.amazonaws.com"

# Criar API key
API_KEY=$(curl -s -X POST $BASE/auth/admin/keys \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "service-key", "description": "Chave interna"}' \
  | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

# Atualizar o secret
API_KEY_B64=$(echo -n "$API_KEY" | base64 -w0)
kubectl patch secret evaluation-service-secret -n evaluation-service \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/SERVICE_API_KEY\", \"value\": \"$API_KEY_B64\"}]"

kubectl rollout restart deployment/evaluation-service -n evaluation-service
```

---

## 7. Formato correto da Targeting Rule

O evaluation-service espera o formato:
```json
{"type": "PERCENTAGE", "value": 50}
```

**NÃO** usar o formato `{"PERCENTAGE": 50}`.

---

## 8. Endpoints disponíveis

Base URL: `http://fiap-ingress-lb-932060456.us-east-1.elb.amazonaws.com`

| Serviço | Método | Endpoint | Auth |
|---|---|---|---|
| auth | POST | `/auth/admin/keys` | MASTER_KEY |
| auth | GET | `/auth/validate` | API_KEY |
| flags | GET/POST | `/flags/flags` | API_KEY |
| flags | GET/PUT/DELETE | `/flags/flags/<name>` | API_KEY |
| targeting | POST | `/targeting/rules` | API_KEY |
| targeting | GET/PUT/DELETE | `/targeting/rules/<flag_name>` | API_KEY |
| evaluation | GET | `/evaluate/evaluate?flag_name=X&user_id=Y` | nenhuma |

---

## 9. Observações importantes (AWS Academy)

- **Credenciais AWS expiram** ao encerrar o lab — repetir o passo 1 a cada nova sessão
- O `EXTERNAL-IP` do ingress-nginx ficará `<pending>` — usar o LB manual criado no passo 5
- Não é possível modificar IAM roles (sem `iam:AttachRolePolicy`)
- O `LabRole` já possui permissões suficientes para EKS, RDS, ElastiCache e SQS
