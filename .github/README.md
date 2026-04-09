# Toggle Master — Tech Challenge [Fase 3]

Turma: **2DCLT** — DevOps e Arquitetura Cloud Pós Tech.

## Integrantes do Grupo

| Nome | RM |
| :--- | :--- |
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | 369367 |

## Documentação de Vídeo

O vídeo técnico detalha o provisionamento via Terraform, a falha proposital na pipeline de segurança e o processo de sincronização do ArgoCD.

- [Link da Demonstração (YouTube)](https://youtube.com/...) 

---

## 1. Visão Geral do Projeto

A Fase 3 do ToggleMaster consolida a transição para o modelo **Everything as Code**. Toda a infraestrutura, segurança e o ciclo de entrega foram automatizados, eliminando intervenções manuais diretas no cluster Kubernetes (EKS).

### Componentes do Ecossistema

| Microsserviço | Linguagem | Responsabilidade | Persistência / Infra |
| :--- | :--- | :--- | :--- |
| **Auth Service** | Go | Gestão de Identidade e API Keys | RDS (PostgreSQL) |
| **Flag Service** | Python | CRUD de Feature Flags | RDS (PostgreSQL) |
| **Targeting Service** | Python | Regras de Segmentação | RDS (PostgreSQL) |
| **Evaluation Service** | Go | Motor de Decisão (Caminho Crítico) | ElastiCache (Redis) |
| **Analytics Service** | Python | Processamento de Eventos | SQS + DynamoDB |

---

## 2. Infraestrutura como Código (Terraform)

O provisionamento da AWS é realizado de forma modular e centralizada, garantindo a replicabilidade do ambiente.

### Recursos Gerenciados

| Recurso | Descrição | Configuração |
| :--- | :--- | :--- |
| **Remote Backend** | S3 + DynamoDB | Armazenamento de Estado Imutável e Lock de Concorrência. |
| **VPC & IA** | Networking | Subnets Isoladas (Privadas/Públicas) e NAT Gateways. |
| **IAM (LabRole)** | Identidade | Integração com AWS Academy utilizando Role pré-existente. |
| **Cluster EKS** | Orquestração | Node Groups Gerenciados com Node Selectors. |
| **RDS Instances** | Databases | 3 Instâncias isoladas para conformidade de dados. |
| **ElastiCache** | Cache | Cluster Redis para alta performance do Evaluation Service. |
| **ECR Repos** | Registry | 5 Repositórios privados com scan de imagem ativado. |

---

## 3. Pipeline CI e DevSecOps (GitHub Actions)

O ciclo de vida de desenvolvimento é blindado por ferramentas de análise estática e segurança. A pipeline é acionada em cada Pull Request e Push na rama `main`.

### Estágios Implementados

| Estágio | Ferramenta | Descrição | Status |
| :--- | :--- | :--- | :--- |
| **Build & Test** | Native Compilers | Compilação e execução de testes unitários. | [x] |
| **Static Analysis** | Linters | Verificação de conformidade de estilo e sintaxe. | [x] |
| **SCA** | **Trivy (fs)** | Análise de vulnerabilidades em bibliotecas de terceiros. | [x] |
| **SAST** | **Gosec / Bandit** | Busca por padrões inseguros no código-fonte em Go e Python. | [ ] |
| **Container Scan** | **Trivy (image)** | Verificação de vulnerabilidades na imagem final gerada. | [x] |
| **Docker Push** | AWS ECR | Envio da imagem tagueada com `COMMIT_SHA`. | [x] |

---

## 4. Fluxo de Entrega Contínua e GitOps

O deploy das aplicações não é mais feito via CLI direta. Adotamos o modelo de **Pull Synchronization** através do GitOps.

### Processo de Sincronização

1.  **Geração do Artefato**: Após a aprovação da pipeline de CI, uma imagem Docker é enviada ao ECR.
2.  **Atualização de Manifesto (GitHub App)**: A pipeline utiliza um **GitHub App** (token de curta duração) para clonar o repositório externo de manifestos ([fiap-dac-toggle-master-gitops](https://github.com/KauanCarvalho/fiap-dac-toggle-master-gitops)). O arquivo `deployment.yaml` é atualizado programaticamente com a nova tag da imagem e o commit é realizado automaticamente no repositório de GitOps.
3.  **Observabilidade e Sync (ArgoCD)**: O ArgoCD monitora o repositório de GitOps. Ao detectar o novo commit, ele identifica o "drift" (diferença) entre o estado desejado (Git) e o estado atual (EKS) e realiza o deploy atômico de forma automática.

### Vantagens do Modelo
- **Single Source of Truth**: O repositório GitOps define exatamente o que está rodando.
- **Auditoria**: Todo deploy tem um registro de autoria via commits do GitHub App.
- **Recuperação de Desastre**: Reinstalar o ambiente completo a partir do ArgoCD leva minutos.

---

## 5. Validação da Integridade do Ecossistema

Para homologar a integração entre os serviços e a infraestrutura Cloud, disponibilizamos um script de exaustão que valida o fluxo do Hot Path (Avaliação de Flags) e a persistência de eventos assíncronos.

### Execução de Testes Automatizados

```bash
# Definir Endereço do Ingress
export INGRESS_URL="http://ad0ec0dcd3d8f4fe6870c68b0ddda408-530315143.us-east-1.elb.amazonaws.com"

# Credenciais de Autenticação
export MASTER_KEY_AUTH_SERVICE="<AUTH_MASTER_KEY>"
export EVALUATION_SERVICE_API_KEY="<SERVICE_API_KEY_VALIDA>"

# Credenciais AWS para Analytics (Sessão Temporária AWS Academy)
export AWS_ACCESS_KEY_ID="<ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<SECRET_KEY>"
export AWS_SESSION_TOKEN="<SESSION_TOKEN>"
export AWS_REGION="us-east-1"

# Mapeamento para o Script
export AUTH_SERVICE_URL="$INGRESS_URL/auth"
export FLAG_SERVICE_URL="$INGRESS_URL/flags"
export TARGETING_SERVICE_URL="$INGRESS_URL/targeting"
export EVALUATION_SERVICE_URL="$INGRESS_URL/evaluate"
export ANALYTICS_SERVICE_URL="$INGRESS_URL/analytics"

# Executar Validação no EKS
./scripts/check/all.sh
```

---

## 6. Conclusão e Conformidade (Opção A — AWS Academy)

Este projeto atende integralmente os requisitos da Fase 3, respeitando as restrições de permissões do ambiente AWS Academy:
1.  **Roles Existentes**: Uso da `LabRole` em todos os módulos Terraform.
2.  **Segurança**: Implementação de scanners SAST/SCA bloqueantes.
3.  **GitOps**: Separação física de repositórios de código e manifestos, orquestrados pelo ArgoCD.
