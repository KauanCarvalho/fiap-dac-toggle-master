# Toggle Master — Tech Challenge [Fase 2]

Turma: _DevOps_ e Arquitetura _Cloud_ Pós _Tech_ — **2DCLT**.

## Integrantes do grupo

| Nome | RM |
|------|----|
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | 369367 |

## Vídeo de Demonstração

**Observação**: Tentaremos ao máximo traduzir o que foi construído pelo grupo ao longo da documentação, mas o vídeo apresenta detalhes técnicos e a **demonstração prática de escalabilidade (HPA)** que podem não estar tão evidentes na leitura.

- [YouTube](https://www.youtube.com/watch?v=LrNKeC5Ae-8).
- [Google Drive](https://drive.google.com/file/d/1ASogE9Jnm5OR0hYGPjPynth36SH6ZNkN/view?usp=drive_link).

## Introdução

Com o sucesso do MVP monolítico na Fase 1, o _ToggleMaster_ evoluiu para uma arquitetura de microsserviços para suportar o aumento de demanda. A **Fase 2** foca na conteinerização, infraestrutura em nuvem e orquestração escalável no **AWS EKS**.

A arquitetura atual conta com 5 microsserviços:

| Serviço | Stack | Função | Infra/Persistência |
| :--- | :---: | :--- | :--- |
| `auth-service` | **Go** | Autenticação e API Keys | PostgreSQL |
| `flag-service` | **Python** | Gestão de Feature Flags | PostgreSQL |
| `targeting-service` | **Python** | Regras de Segmentação | PostgreSQL |
| `evaluation-service` | **Go** | Decisão Final (Hot Path) | Redis |
| `analytics-service` | **Python** | Analytics e Eventos | SQS + DynamoDB |

> [!NOTE]
> Os repositórios base dos serviços foram originados de [FIAP-TCs](https://github.com/FIAP-TCs). Foram realizadas pequenas adaptações técnicas nas aplicações, como ajustes de dependências, remoção de importações não utilizadas e atualizações de versões (*bumps*) para garantir a estabilidade e integração do ecossistema.

---

## Estrutura do Projeto

### Diretórios Principais

*   [`k8s/`](./k8s/): Manifestos Kubernetes (Kustomize) organizados por serviço para implantação no cluster EKS.
*   [`local/services/`](./local/services/): Código-fonte e Dockerfiles otimizados dos 5 microsserviços:
    *   `auth-service/`: Autenticação e API Keys (Go/Gin + PostgreSQL).
    *   `flag-service/`: Gestão de Feature Flags (Python/Flask + PostgreSQL).
    *   `targeting-service/`: Regras de Segmentação (Python/Flask + PostgreSQL).
    *   `evaluation-service/`: Decisor de Hot Path (Go/Gin + Redis).
    *   `analytics-service/`: Coleta de Métricas (Python/Boto3 + SQS/DynamoDB).
*   [`scripts/check/`](./scripts/check/): Scripts de automação para testes de integração e validação de saúde.
*   [`.github/docs/`](./.github/docs/): Documentação técnica detalhada ([Deploy](.github/docs/deployment.md) e [Checklist](.github/docs/checklist-before-deploy.md)).

### Arquivos na Raiz (Root)

*   [`Makefile`](./Makefile): Ponto central para comandos de automação (build, setup, test, clean).
*   [`docker-compose.yml`](./docker-compose.yml): Orquestração completa de 9 contêineres para o ecossistema local.
*   [`.env.sample`](./.env.sample): Guia de variáveis de ambiente obrigatórias para execução.

### Scripts de Verificação (`scripts/check/`)

Cada microsserviço possui uma bateria de testes específica para validar sua prontidão:

*   [`_common.sh`](./scripts/check/_common.sh): Funções auxiliares e utilitários compartilhados entre os scripts de teste.
*   [`all.sh`](./scripts/check/all.sh): Orquestrador que executa todos os scripts abaixo em sequência.
*   [`analytics-service.sh`](./scripts/check/analytics-service.sh): Valida o consumo de eventos SQS e persistência no DynamoDB.
*   [`auth-service.sh`](./scripts/check/auth-service.sh): Valida a geração de API Keys e autenticação `Bearer`.
*   [`evaluation-service.sh`](./scripts/check/evaluation-service.sh): Testa o caminho crítico de decisão final e integração com Redis.
*   [`flag-service.sh`](./scripts/check/flag-service.sh): Testa o CRUD de flags de funcionalidades.
*   [`targeting-service.sh`](./scripts/check/targeting-service.sh): Valida as regras complexas de segmentação de usuários.
*   [`teste-k8s.sh`](./scripts/check/teste-k8s.sh): Bateria de testes de integração para validação do ambiente em nuvem (EKS/Ingress).

---

## Requisitos Técnicos

### 1. Análise e Conteinerização (Docker)

O primeiro passo garante a execução e compreensão de todo o ecossistema localmente antes da implantação em nuvem.

#### Arquivos Técnicos
*   **Dockerfiles Otimizados**: Utilizam **multi-stage builds** para reduzir o tamanho das imagens e aumentar a segurança (Go/Distroless e Python/Slim).
    *   [`auth-service`](../local/services/auth-service/Dockerfile)
    *   [`flag-service`](../local/services/flag-service/Dockerfile)
    *   [`targeting-service`](../local/services/targeting-service/Dockerfile)
    *   [`evaluation-service`](../local/services/evaluation-service/Dockerfile)
    *   [`analytics-service`](../local/services/analytics-service/Dockerfile)
*   **Orquestração Local**: O arquivo [docker-compose.yml](../docker-compose.yml) centraliza os 5 serviços e 4 infraestruturas (2x Postgres, 1x Redis, 1x LocalStack/DynamoDB).

#### Funcionalidades Entregues
- [x] **Dockerfiles Otimizados**: Imagens robustas utilizando multi-stage builds e usuários non-root.
- [x] **Race Conditions Tratadas**: Healthchecks garantem que os serviços só iniciem após a prontidão dos bancos via `depends_on`.
- [x] **Infraestrutura Cloud Local**: Simulação de _SQS_ e _DynamoDB_ via _LocalStack_ para testes de mensageria.

#### Execução e Comandos (Makefile)

Para listar todos os comandos disponíveis, utilize `make help`. A sequência recomendada para inicialização completa é:

1.  **Limpeza Global**: `make kaboom`
    *   Remove containers, volumes, redes e imagens locais, garantindo um ambiente "virgem" para o teste.
2.  **Subir Ambiente**: `make docker-up`
    *   Constrói e inicia os 9 containers (5 serviços + 4 infra) em modo _detached_.
3.  **Configurar AWS Local**: `make localstack-setup`
    *   Provisiona as filas SQS e tabelas DynamoDB no _LocalStack_ para os serviços de mensageria e análise.
4.  **Validar Execução**: `make check-all`
    *   Invoca o script [all.sh](../scripts/check/all.sh), que coordena a execução de todos os testes de integração específicos:
        *   [`auth-service.sh`](../scripts/check/auth-service.sh): Valida geração de API Keys.
        *   [`flag-service.sh`](../scripts/check/flag-service.sh) e [`targeting-service.sh`](../scripts/check/targeting-service.sh): Validam regras de Toggle.
        *   [`evaluation-service.sh`](../scripts/check/evaluation-service.sh): Testa o motor de decisão e cache Redis.
        *   [`analytics-service.sh`](../scripts/check/analytics-service.sh): Valida o consumo de eventos SQS e persistência em DynamoDB.

[local.webm](https://github.com/user-attachments/assets/7f53cd2f-c247-4301-bf90-86cbbdbe3347)

---

### 2. Provisionamento de Infraestrutura Cloud (AWS)

Próximos passos na infraestrutura da AWS (para implantação no Kubernetes).

> [!NOTE]
> Para detalhes avançados de infraestrutura e procedimentos de implantação, consulte os guias na pasta [`docs`](.github/docs/):
>
> *   [**Guia de Deploy em Produção (EKS)**](.github/docs/deployment.md)
> *   [**Checklist Pré-Deploy**](.github/docs/checklist-before-deploy.md)

---

### Repositórios de Container
- [x] Criar 5 repositórios no AWS ECR.
- [x] Realizar build e publicar todas as imagens Docker locais para o ECR.

### Databases (Cloud Provider)
- [x] Provisionar RDS 1: PostgreSQL para o `auth-service`.
- [x] Provisionar RDS 2: PostgreSQL para o `toggle-db` (compartilhado entre `flag-service` e `targeting-service`).
  - **Justificativa da Consolidação**: O `auth-service` guarda informações sensíveis (hashes de chaves de acesso), portanto seu isolamento em um banco de dados dedicado é crítico por segurança. Por outro lado, `flag-service` e `targeting-service` compartilham o mesmo domínio lógico (gerenciamento e regras de feature toggles). Consolidar esses dois serviços em uma única instância RDS (`toggle-db`) com esquemas separados é o ideal para reduzir os custos desnecessários do MVP na AWS sem abrir mão da segurança essencial.
- [x] Provisionar ElastiCache 1: Cluster Redis para o `evaluation-service`.
- [x] Provisionar DynamoDB: Tabela para salvar dados do `analytics-service`.
- [x] Provisionar SQS: Fila do tipo Standard (produtor: evaluation, consumidor: analytics).

### Documentação Detalhada
Para o processo completo de provisionamento e configuração de cada recurso acima, consulte o [**Guia de Deploy**](.github/docs/deployment.md).

---

## 3. Configuração do Cluster Kubernetes (EKS)

- [x] Instalar as ferramentas de apoio (Helm e eksctl).
- [x] Criar Cluster EKS e os *Managed Node Groups*.
- [x] Instalar o **Metrics Server** no cluster (Necessário para a automação do HPA escalar usando CPU).
- [x] Configurar **Nginx Ingress Controller** visando associar ALB/NLB à AWS de modo externo. 

---

## 4. Orquestração e Implantação (Manifestos Kubernetes)

Desenvolvimento dos `.yaml` para o Deploy no EKS. Seguindo as boas práticas operacionais:

- [x] **Namespaces** lógicos e apartados.
- [x] **Deployments** conectando aos 5 repositórios ECR.
- [x] **Services** locais (ClusterIP).
- [x] **Secrets** codificadas em base64 para as "strings de conexão" e AWS Secrets injetadas.
- [x] **ConfigMaps** configurando URIs dos serviços em rotas internas.
- [x] **Ingress Manifest** aplicando regras de roteamentos externos (`/auth` cai em Auth, `/flags` cai no Flag, etc).
- [x] Implementar obrigatoriamente *Requests e Limits* nas specs.
- [x] Injetar as proteções *LivenessProbe* e *ReadinessProbe*.

> [!TIP]
> Antes de aplicar os manifestos, certifique-se de seguir o [**Checklist Pré-Deploy**](.github/docs/checklist-before-deploy.md) para garantir que todos os placeholders e segredos foram preenchidos corretamente.

---

## 5. Configuração de Escalabilidade Automática

- [x] Implementar **HPA (Horizontal Pod Autoscaler)** focado em percentual de CPU (exemplo 70% CPU) para lidar com tráfego sazonal no `evaluation-service`.
- [x] Integrar monitoramento para simulação de estresse, gerando carga assíncrona (Postman / hey).
- [x] Implementação de Auto-Escalonamento para o **`analytics-service`**. Faremos KEDA (Kubernetes Event-driven Autoscaling) usando tamanho de fila (`queueDepth`) como métrica de aumento de Workers se preferido na arquitetura Cloud ideal.

---

## Conclusão: Atendimento aos Requisitos (Opção A — AWS Academy)

Este projeto foi desenvolvido e validado seguindo as diretrizes da **Opção A** do Desafio (Ambiente AWS Academy). Todos os critérios técnicos foram atendidos com sucesso, utilizando a `LabRole` como base para permissões e aplicando os _workarounds_ necessários para as limitações de IAM:

1.  **Conteinerização**: Dockerfiles otimizados e orquestração local via `docker-compose.yml` (5 serviços + 4 infra).
2.  **Infraestrutura Cloud**: Provisionamento de 5 repositórios ECR, 2 instâncias RDS (consolidando domínios lógicos), clusters ElastiCache, além de DynamoDB e SQS.
3.  **Kubernetes (EKS)**: Cluster e Node Groups criados manualmente e associados à `LabRole`, com Metrics Server e Nginx Ingress Controller operacionais.
4.  **Orquestração**: Manifestos organizados em Namespaces, com uso de Secrets (base64), ConfigMaps, Ingress, e definições de Liveness/Readiness Probes e Requests/Limits.
5.  **Escalabilidade**: Implementação de HPA focado em CPU para o `evaluation-service` e `analytics-service`, garantindo a elasticidade necessária para o ecossistema mesmo sob as restrições de criação de novas Roles (sem suporte a IRSA para KEDA).
