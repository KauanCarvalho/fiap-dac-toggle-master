# Toggle Master Microsserviços — Tech Challenge Fase 2

Turma: DevOps e Arquitetura Cloud Pós Tech — **2DCLT**.

## Vídeo de Demonstração

*(A ser adicionado - Link do YouTube)*

---

## Integrantes do grupo

| Nome | RM |
|------|----|
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | 369367 |

---

## Introdução

O MVP monolítico do ToggleMaster implantado na Fase 1 foi um sucesso. Com o aumento da demanda, a arquitetura monolítica começou a apresentar gargalos. Para evolução, o ToggleMaster foi reescrito como um ecossistema de microsserviços distribuídos. 

O escopo da **Fase 2** envolve conteinerizar, provisionar a infraestrutura de nuvem, e implantar as métricas e orquestração num ambiente escalável no Kubernetes da AWS (EKS).

A arquitetura atual possui 5 microsserviços:
- **`auth-service` (Go)**: Gerencia chaves de API e autenticação. (Banco: PostgreSQL).
- **`flag-service` (Python)**: CRUD das definições das feature flags. (Banco: PostgreSQL).
- **`targeting-service` (Python)**: Gerencia regras complexas de segmentação. (Banco: PostgreSQL).
- **`evaluation-service` (Go)**: Caminho quente (hot path) para retorno da decisão final (true/false). (Cache: Redis).
- **`analytics-service` (Python)**: Consome eventos de uma fila e salva dados de análise. (Fila: AWS SQS, Banco: AWS DynamoDB).

---

## 1. Análise e Conteinerização (Docker local)

O primeiro passo é garantir a execução local estável do ecossistema e dos 4 bancos de dados antes de ir para a nuvem.

### O que já foi feito ✅
- [x] **Dockerfiles Otimizados**: Todos os 5 microsserviços possuem Dockerfiles robustos utilizando **multi-stage builds**. As imagens Go utilizam `distroless` e as Python `slim`, reduzindo vetores de ataque e executando a aplicação sob usuário `non-root`.
- [x] **Docker Compose Orquestrado**: Criado arquivo `docker-compose.yml` que sobe 9 containers simultaneamente (5 serviços e 4 infraestruturas de banco). 
- [x] **Infraestrutura Local**: Subimos 2 Postgres, 1 Redis e utilizamos o **LocalStack** para simular o AWS SQS (filas) e o DynamoDB (tabelas) em ambiente local.
- [x] **Race Conditions Tratadas**: Implementado `healthcheck` robusto. Os serviços da aplicação estritamente aguardam a prontidão (`service_healthy`) de seus respectivos bancos (Postgres, Redis ou LocalStack) via instrução `depends_on`.
- [x] **Solução Auth-Proxy**: Resolvidos gargalos de "Service-to-Service Authentication" com *database seeding* para facilitar o spin-up sem intervenção manual.
- [x] **Automação de Qualidade Global**: Criada uma bateria de testes `make check-all` em bash, simulando validações lógicas e consumo das filas como seria exigido localmente.

---

## 2. Provisionamento de Infraestrutura Cloud (AWS)

Próximos passos na infraestrutura da AWS (para implantação no Kubernetes).

### Repositórios de Container
- [ ] Criar 5 repositórios no AWS ECR.
- [ ] Realizar build e publicar todas as imagens Docker locais para o ECR.

### Databases (Cloud Provider)
- [ ] Provisionar RDS 1: PostgreSQL para o `auth-service`.
- [ ] Provisionar RDS 2: PostgreSQL para o `toggle-db` (compartilhado entre `flag-service` e `targeting-service`).
  - **Justificativa da Consolidação**: O `auth-service` guarda informações sensíveis (hashes de chaves de acesso), portanto seu isolamento em um banco de dados dedicado é crítico por segurança. Por outro lado, `flag-service` e `targeting-service` compartilham o mesmo domínio lógico (gerenciamento e regras de feature toggles). Consolidar esses dois serviços em uma única instância RDS (`toggle-db`) com esquemas separados é o ideal para reduzir os custos desnecessários do MVP na AWS sem abrir mão da segurança essencial.
- [ ] Provisionar ElastiCache 1: Cluster Redis para o `evaluation-service`.
- [ ] Provisionar DynamoDB: Tabela para salvar dados do `analytics-service`.
- [ ] Provisionar SQS: Fila do tipo Standard (produtor: evaluation, consumidor: analytics).

---

## 3. Configuração do Cluster Kubernetes (EKS)

- [ ] Instalar as ferramentas de apoio (Helm e eksctl).
- [ ] Criar Cluster EKS e os *Managed Node Groups*.
- [ ] Instalar o **Metrics Server** no cluster (Necessário para a automação do HPA escalar usando CPU).
- [ ] Configurar **Nginx Ingress Controller** visando associar ALB/NLB à AWS de modo externo. 

---

## 4. Orquestração e Implantação (Manifestos Kubernetes)

Desenvolvimento dos `.yaml` para o Deploy no EKS. Seguindo as boas práticas operacionais:

- [ ] **Namespaces** lógicos e apartados.
- [ ] **Deployments** conectando aos 5 repositórios ECR.
- [ ] **Services** locais (ClusterIP).
- [ ] **Secrets** codificadas em base64 para as "strings de conexão" e AWS Secrets injetadas.
- [ ] **ConfigMaps** configurando URIs dos serviços em rotas internas.
- [ ] **Ingress Manifest** aplicando regras de roteamentos externos (`/auth` cai em Auth, `/flags` cai no Flag, etc).
- [ ] Implementar obrigatoriamente *Requests e Limits* nas specs.
- [ ] Injetar as proteções *LivenessProbe* e *ReadinessProbe*.

---

## 5. Configuração de Escalabilidade Automática

- [ ] Implementar **HPA (Horizontal Pod Autoscaler)** focado em percentual de CPU (exemplo 70% CPU) para lidar com tráfego sazonal no `evaluation-service`.
- [ ] Integrar monitoramento para simulação de estresse, gerando carga assíncrona (Postman / hey).
- [ ] Implementação de Auto-Escalonamento para o **`analytics-service`**. Faremos KEDA (Kubernetes Event-driven Autoscaling) usando tamanho de fila (`queueDepth`) como métrica de aumento de Workers se preferido na arquitetura Cloud ideal.

---

## Guia de Teste (Local)

Para rodar todo o ambiente local pronto em Docker, do zero:

1. Suba todo o ecossistema:
   ```bash
   make docker-up
   ```

2. Inicialize as tabelas do LocalStack para simular a AWS localmente:
   ```bash
   make localstack-setup
   ```

3. Rode toda a bateria global de verificação:
   ```bash
   make check-all
   ```

4. Para desligar:
   ```bash
   make docker-down
   ```
