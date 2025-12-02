# Toggle Master Monolith — Tech Challenge Fase 1

Turma: DevOps e Arquitetura Cloud Pós Tech — **2DCLT**.

---

## Integrantes do grupo

| Nome | RM |
|------|----|
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | xxxxxxxx |

---

## 1. Requisitos Técnicos

### 1.1 Execute a aplicação monolítica toggle-master-monolith localmente para entender seu funcionamento

A aplicação [toggle master monolith](https://github.com/dougls/toggle-master-monolith) foi executada localmente utilizando Docker, garantindo reprodutibilidade e isolamento. Durante a execução foram observados:

[x] Comportamento dos endpoints expostos (`GET /health`, `POST /flags`, `GET /flags`, `GET /flags/<nome-da-flag>`, `PUT /flags/<nome-da-flag>`).
[x] Ciclo de vida das feature flags.
[x] Resposta a operações de leitura, criação e atualização.
[x] Fluxo esperado da aplicação como um serviço único.

Para facilitar a validação, um [script](./testdata/test-endpoints.sh) de testes foi criado, ele executa, em sequência:

[x] Verificação do healthcheck.
[x] Consulta a uma flag inexistente.
[x] Listagem de todas as flags.
[x] Criação de uma nova flag.
[x] Consulta da flag criada.
[x] Atualização da flag.
[x] Listagem final validando o estado atualizado.

Esse mesmo script será utilizado no ambiente de **"produção" na cloud**, validando consistência entre ambientes.

---

### 1.2 Analise o código e identifique por que ele é considerado um "monolito". Discuta as vantagens e desvantagens dessa abordagem para um MVP

O projeto [toggle master monolith](https://github.com/dougls/toggle-master-monolith) apresenta características clássicas de um monólito. Toda a base de código e toda a lógica de negócio residem em um único serviço, compilado e executado como um único artefato. Não há módulos independentes, _boundaries_ explícitos ou divisão por domínios. Em produção, esse serviço é executado como um processo único, responsável por todas as funcionalidades.

Essa arquitetura é reforçada pelos seguintes aspectos:

1. Único repositório central contendo toda a lógica da aplicação.
2. Ausência de microsserviços ou serviços independentes.
3. Deploy único, gerando um único binário/processo.
4. Acoplamento entre camadas internas, compartilhando o mesmo ciclo de vida.

#### Vantagens para um MVP

1. **Velocidade de desenvolvimento**: equipes pequenas conseguem evoluir rapidamente sem overhead arquitetural.
2. **Simplicidade operacional**: deploy único, sem orquestração de serviços.
3. **Baixo custo**: reduz o esforço de manutenção inicial e evita complexidade prematura.
4. **Menos pontos de falha**: centralização facilita testes e controle de versão.

#### Desvantagens em evolução e escala

1. **Escalabilidade limitada**: não é possível escalar partes específicas de forma independente.
2. **Deploy arriscado**: qualquer alteração requer redistribuição da aplicação inteira.
3. **Acoplamento entre domínios**: mudanças em uma área podem afetar outras.
4. **Complexidade crescente**: com o tempo tende a se tornar um monólito rígido, de difícil manutenção.
5. **Dificuldade de migração**: a separação posterior é mais custosa do que projetar módulos desde o início.

Dessa forma, embora o monólito seja adequado para o escopo de um MVP, ele impõe desafios significativos quando a aplicação demanda escalabilidade, governança modular e evolução de longo prazo.

---

### 1.3 Leia e compreenda os 12 Fatores (12-Factor App) e identifique quais deles a aplicação já atende e quais precisariam de ajustes para um ambiente de produção mais robusto

A tabela abaixo analisa o alinhamento da aplicação aos princípios do **12-Factor App**, padrão amplamente adotado para aplicações modernas, especialmente em nuvem.

| Fator | Atende | Observações Técnicas |
|-------|--------|-----------------------|
| **1. Código Base** | Atende parcialmente | Um único repositório contém toda a aplicação, adequado para monólitos. Contudo, não há estrutura modular clara. |
| **2. Dependências** | Não atende | Dependências não são explicitamente declaradas de forma isolada ou versionadas conforme boas práticas. |
| **3. Configurações** | Não atende | A aplicação não utiliza variáveis de ambiente para configuração; ajustes são feitos diretamente no código. |
| **4. Serviços de Apoio** | Atende parcialmente | Utiliza serviços externos, porém sem desacoplamento formal via configuração externa. |
| **5. Build, Release e Run** | Não atende | Não há separação efetiva entre fases de construção, release e execução; o ciclo é acoplado. |
| **6. Processos** | Atende parcialmente | O processo é único e stateless na prática, porém sem definição explícita para execução concorrente. |
| **7. Vínculo de Portas** | Atende | A aplicação expõe sua própria porta, permitindo execução autônoma. |
| **8. Concorrência** | Atende parcialmente | O modelo de processo único limita concorrência. Escala horizontal não é trivial. |
| **9. Descarte** | Não atende completamente | Não há mecanismos de shutdown gracioso nem gestão de processos formalizada. |
| **10. Dev/Prod Parity** | Não atende | Não há equivalência adequada entre ambientes; configurações fixas e ausência de padrões de ambiente prejudicam o alinhamento. |
| **11. Logs** | Atende parcialmente | Logs são emitidos via stdout, conforme recomendado, porém sem formatação ou estrutura tratável. |
| **12. Administração de Processos** | Não atende | Não existem processos administrativos executáveis ou segregados. |

**Conclusão geral**: A aplicação atende parcialmente alguns fatores básicos (porta, logs simples, repositório único), mas carece de práticas essenciais para operação em nuvem, como externalização de configurações, modularização de dependências e paridade entre ambientes. Esses fatores tornam necessária uma reestruturação para um ambiente de produção robusto.

---

## 2. Arquitetura Cloud (estrutura pronta, sem respostas)

### 2.1 Desenhe um diagrama de arquitetura simples para hospedar a aplicação na AWS. O diagrama deve incluir: Uma VPC com sub-redes públicas e privadas, Uma instância EC2 na sub-rede pública para rodar a aplicação, Um RDS (PostgreSQL ou MySQL) na sub-rede privada para o banco de dados, Um Security Group para a EC2 permitindo tráfego HTTP/HTTPS e SSH (de um IP específico) e Um Security Group para o RDS permitindo tráfego apenas do Security Group da EC2

{TODO}

### 2.2 Faça uma estimativa de custo mensal para essa arquitetura usando a Calculadora de Preços da AWS

{TODO}

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
