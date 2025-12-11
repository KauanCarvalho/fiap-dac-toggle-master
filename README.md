# Toggle Master Monolith — Tech Challenge Fase 1

Turma: DevOps e Arquitetura Cloud Pós Tech — **2DCLT**.

---

## Integrantes do grupo

| Nome | RM |
|------|----|
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | 369367 |

---

## 1. Requisitos Técnicos

### 1.1 Execute a aplicação monolítica toggle-master-monolith localmente para entender seu funcionamento

A aplicação [toggle master monolith](https://github.com/dougls/toggle-master-monolith) foi executada localmente utilizando Docker, garantindo reprodutibilidade e isolamento. Durante a execução foram observados:

- [x] Comportamento dos endpoints expostos (`GET /health`, `POST /flags`, `GET /flags`, `GET /flags/<nome-da-flag>`, `PUT /flags/<nome-da-flag>`).
- [x] Ciclo de vida das feature flags.
- [x] Resposta a operações de leitura, criação e atualização.
- [x] Fluxo esperado da aplicação como um serviço único.

Para facilitar a validação, um [script](./testdata/test-endpoints.sh) de testes foi criado, ele executa, em sequência:

- [x] Verificação do healthcheck.
- [x] Consulta a uma flag inexistente.
- [x] Listagem de todas as flags.
- [x] Criação de uma nova flag.
- [x] Consulta da flag criada.
- [x] Atualização da flag.
- [x] Listagem final validando o estado atualizado.

Esse mesmo script será utilizado no ambiente de **"produção" na cloud**, validando consistência entre ambientes.

https://github.com/user-attachments/assets/d7cc8f76-9688-4c4b-915b-ba3333e4cde8

---

### 1.2 Analise o código e identifique por que ele é considerado um "monolito". Discuta as vantagens e desvantagens dessa abordagem para um MVP

O projeto [toggle master monolith](https://github.com/dougls/toggle-master-monolith) apresenta características clássicas de um monólito. Toda a base de código e toda a lógica de negócio residem em um único serviço, compilado e executado como um único artefato. Não há módulos independentes, _boundaries_ explícitos ou divisão por domínios. Em produção, esse serviço é executado como um processo único, responsável por todas as funcionalidades.

Essa arquitetura é reforçada pelos seguintes aspectos:

1. Único repositório central contendo toda a lógica da aplicação.
2. Ausência de microsserviços ou serviços independentes.
3. Deploy único, gerando um único binário/processo.
4. Acoplamento entre camadas internas, compartilhando o mesmo ciclo de vida.

#### Vantagens para um MVP

1. **Velocidade de desenvolvimento**: Equipes pequenas conseguem evoluir rapidamente sem overhead arquitetural,  reduzindo a complexidade inicial do projeto. Isso possibilita uma entrega mais rápida para testar se o _MVP_ atende às necessidades.
2. **Simplicidade operacional**: Deploy único, sem orquestração de serviços.
3. **Baixo custo**: Reduz o esforço de manutenção inicial e evita complexidade prematura.
4. **Menos pontos de falha**: Centralização facilita testes e controle de versão, assim como reduz a latência entre serviços, pelo fato de não existir comunicação em rede entre diferentes componentes.
5. **Debugging facilitado**: Como toda a lógica se encontra em um único lugar, o rastreamento de bugs e inconsistências é mais simples em aplicações menores como um _MVP_.
6. **Teste e integração simplificados**: Integração contínua e testes end-to-end tendem a ser mais diretos, pois não há necessidade de simular múltiplos serviços distribuídos.
7. **Simplicidade de observabilidade**: Logs, métricas e tracing estão concentrados em um único processo, o que facilita a correlação de eventos durante o troubleshooting.

#### Desvantagens em evolução e escala

1. **Escalabilidade limitada**: Não é possível escalar partes específicas de forma independente.
2. **Deploy arriscado**: Qualquer alteração requer redistribuição da aplicação inteira.
3. **Acoplamento entre domínios**: Mudanças em uma área podem afetar outras.
4. **Complexidade crescente**: Com o tempo tende a se tornar um monólito rígido, de difícil manutenção.
5. **Dificuldade de migração**: A separação posterior é mais custosa do que projetar módulos desde o início.
6. **Tempo de build/deploy maiores**: A cada alteração é preciso construir e validar o artefato inteiro, o que aumenta a latência de entrega.
7. **Dificuldade de adotar novas tecnologias**: Tornar partes do sistema em outras linguagens ou frameworks exige reescrita e rompe o deploy unificado.
8. **Maior vulnerabilidade**: Um bug ou vulnerabilidade pode impactar todo o produto em vez de apenas um serviço isolado.

Dessa forma, embora o monólito seja adequado para o escopo de um _MVP_, ele impõe desafios significativos quando a aplicação demanda escalabilidade, governança modular e evolução de longo prazo. Porém considerando o contexto da proposta, iniciar com uma arquitetura monolítica não é apenas aceitável, é recomendado para o MVP. O foco desta fase deve estar em validar se existe demanda real pelo produto, não em construir a arquitetura perfeita.

---

### 1.3 Leia e compreenda os 12 Fatores (12-Factor App) e identifique quais deles a aplicação já atende e quais precisariam de ajustes para um ambiente de produção mais robusto

Antes de avaliarmos se a aplicação atende ou não aos princípios do **12-Factor App**, precisamos entender o que são esses fatores e por que eles existem. O _Twelve-Factor App_ é uma metodologia criada para orientar a construção de aplicações modernas, especialmente aplicações entregues como serviço (Software as a Service – SaaS).

#### A ideia é permitir que a aplicação

1. Seja fácil de configurar e manter.
2. Tenha alta portabilidade entre máquinas e ambientes.
3. Funcione bem em plataformas de nuvem.
4. Reduza diferenças entre desenvolvimento e produção.
5. Escale de forma previsível e segura.

A tabela abaixo analisa o alinhamento da aplicação aos princípios do **12-Factor App**, padrão amplamente adotado para aplicações modernas, especialmente em nuvem.

| Fator | Definição | Atende | Observações Técnicas |
|-------|-----------|--------|----------------------|
| **1. Codebase** (Base de Código) | Uma única base de código versionada, podendo gerar múltiplos deploys | Atende | A aplicação possui um único repositório Git, mas é o suficiente para garantir rastreabilidade |
| **2. Dependencies** (Dependências) | Declare e isole dependências de forma explícita | Atende | As dependências estão em um arquivo aparte, requirements.txt. Sendo declaradas as versões exatas de cada dependência. |
| **3. Config** (Configurações) | Armazene as configurações no ambiente, não no código | Atende parcialmente | Variáveis críticas como credenciais e parâmetros de banco são externalizadas, mas parte da configuração está fixa no código ou depende de defaults como a porta de execução. |
| **4. Backing Services** (Serviços de Apoio) | Trate serviços externos como recursos plugáveis | Atende | Usa o Banco PostgreSQL como serviço anexado via configuração. |
| **5. Build, Release, Run** | Separe claramente as etapas de build, release e execução | Não atende | Apesar do Dockerfile permitir um processo de build, a aplicação não possui pipeline ou mecanismos formais que separem build, release e run. O ciclo é acoplado. |
| **6. Processes** (Processos) | Executar como processos stateless, sem guardar estado local | Atende | A aplicação não guarda dados na memória, todos os dados ficam em banco, se reiniciar a aplicação, não se perde nada. |
| **7. Port Binding** | Expor o serviço via port binding próprio | Atende parcialmente | A porta 5000 está fixa no código, não pode mudar a porta sem alterar o código, deveria ser uma variável de ambiente PORT. Mas como será rodado em Docker, a configuração permite rodar em outra porta. EX docker run -p 8080:5000 togglemaster |
| **8. Concurrency** (Concorrência) | Escalar através de múltiplos processos | Atende parcialmente | O monólito pode escalar com múltiplas instâncias (Docker, EC2), porém o design não facilita escalabilidade granular ou paralelismo interno. |
| **9. Disposability** (Descartabilidade) | Processos devem iniciar e parar rapidamente, com shutdown gracioso | Atende parcialmente | A aplicação inicia rapidamente e ao encerrar, o Gunicorn faz graceful shutdown básico, aguardando um breve período para que possíveis requisições terminem. |
| **10. Dev/Prod Parity** | Manter ambientes de desenvolvimento e produção o mais similares possível | Atende | Mesmo o ambiente de Dev e Prod serem diferentes, já que um roda local e outro dentro da AWS, pois irá rodar dentro de um docker, assim criando condições iguais para ambos os ambientes. |
| **11. Logs** | Tratar logs como fluxo de eventos contínuos | Atende parcialmente | Logs são enviados ao stdout, o que é recomendado. Porém, não possuem estrutura consistente, metadados ou integração fácil com agregadores. |
| **12. Admin Processes** | Executar operações administrativas como processos separados | Atende parcialmente | Tem comandos CLI como por exemplo,  para inicializar banco com flask init-db. Mas não tem um sistema de migrations. |

**Conclusão geral**: A aplicação atende parcialmente alguns fatores básicos (porta, logs simples, repositório único), mas carece de práticas essenciais para operação em nuvem, como externalização de configurações, modularização de dependências e paridade entre ambientes. Esses fatores tornam necessária uma reestruturação para um ambiente de produção robusto.

---

## 2. Arquitetura Cloud (estrutura pronta, sem respostas)

### 2.1 Desenhe um diagrama de arquitetura simples para hospedar a aplicação na AWS.

#### O diagrama deve incluir

- [x] Uma VPC com sub-redes públicas e privadas.
- [x] Uma instância EC2 na sub-rede pública para rodar a aplicação.
- [x] Um RDS (PostgreSQL ou MySQL) na sub-rede privada para o banco de dados.
- [x] Um Security Group para a EC2 permitindo tráfego HTTP/HTTPS e SSH (de um IP específico).
- [x] Um Security Group para o RDS permitindo tráfego apenas do Security Group da EC2.

![Diagrama de arquitetura simples](https://github.com/user-attachments/assets/1f052458-1b62-4517-82fb-bc1beb5412bb)

Para este MVP, optamos por uma arquitetura implantada em uma única região e uma única zona de disponibilidade (Single-AZ), mantendo o ambiente simples, funcional e com custos reduzidos, sem comprometer a funcionalidade necessária. A escolha se fundamenta principalmente por se tratar de um escopo de _MVP_ com custo significativamente inferior, latência otimizada e menor complexidade operacional.

### 2.2 Faça uma estimativa de custo mensal para essa arquitetura usando a Calculadora de Preços da AWS

A estimativa foi baseada na arquitetura mínima necessária para executar a aplicação [toggle master monolith](https://github.com/dougls/toggle-master-monolith) com baixa latência e persistência confiável, utilizando:

- 1 instância EC2 para o monólito.
- 1 instância RDS PostgreSQL.
- Itens obrigatórios de rede (gratuitos).

[Estimativa oficial](https://calculator.aws/#/estimate?id=0a109df2fe24e5de3f7b959e1fbe44eeccee9150).  

---

### Tabela de Custos Mensais

| Serviço | Configuração | Custo Mensal |
|--------|--------------|--------------|
| **Amazon EC2** | t3.micro, Linux, 20GB gp3 | **$6.13** |
| **RDS PostgreSQL** | db.t4g.micro, Single-AZ, 20GB gp3 | **$64.52** |
| **Transferência de Dados** | 1GB para internet | **$0.09** |
| **Itens obrigatórios gratuitos** | VPC, Subnets, SGs, Route Tables, IAM, IGW, CloudWatch básico | **$0.00** |
| **Total Estimado** | — | **$70.74 / mês** |

---

## 2.3.1 Justificativa da Escolha dos Serviços (com prós e contras)

### **EC2 – t3.micro**

Instância para rodar o _app_.

#### Prós

- Custo baixo.
- Bom para workloads pequenos.
- CPU creditada (burst) ajuda em picos.

#### Contras

- 1 GB RAM impõe limites
- É ponto único de falha
- Região São Paulo é mais cara do que us-east-1

---

### RDS PostgreSQL – db.t4g.micro (Single-AZ)

Banco gerenciado com storage GP3.

#### Prós

- Alta confiabilidade
- Backup automático incluído
- Storage escalável
- Integração simples com Go

#### Contras

- É o componente mais caro da solução
- Single-AZ não possui failover automático
- Armazenamento I/O impacta custo final

---

### Rede e Itens Obrigatórios (gratuitos)

Inclui: VPC, Subnets, Security Groups, Route Tables, Internet Gateway, IAM e CloudWatch básico.

#### Prós

- Não geram custo adicional
- Conjunto mínimo necessário para operar a arquitetura

#### Contras

- Não substituem serviços pagos como NAT Gateway ou ALB caso o projeto cresça
- Exigem configuração manual ou via IaC

---

## 2.3.2 Conclusão da Estimativa

O valor final aproximado de **$70.74/mês** em São Paulo reflete uma arquitetura mínima, porém funcional.  

A escolha **privilegia**:

- Baixa latência regional  
- Simplicidade operacional  
- Custo controlado  
- Infraestrutura gerenciada sempre que possível  

A **estrutura pode ser expandida** futuramente com:

- Auto Scaling  
- Load Balancer (ALB)  
- RDS Proxy  
- Subnets privadas + NAT Gateway  
- TLS/HTTPS gerenciado  

Sem alterar a lógica da aplicação.

---

## 3. AWS (Prático)

{TODO}

Checklist para execução:

| Tarefa | Status |
|--------|--------|
| Provisionar infraestrutura manualmente | pendente |
| Conectar via SSH | pendente |
| Instalar dependências na EC2 (Python, pip, etc.) e o códigofonte | pendente |
| Configurar credenciais e variáveis de ambiente | pendente |
| Conectar à instância RDS | pendente |
| Executar a aplicação na EC2 | pendente |
| Validar acesso público | pendente |

[Vídeo demonstrativo (em breve)](https://www.youtube.com/)

---

## 4. Referências

- [Repositório oficial](https://github.com/dougls/toggle-master-monolith).
- [12-Factor App](https://12factor.net).
- [Calculadora AWS](https://calculator.aws/#/).
