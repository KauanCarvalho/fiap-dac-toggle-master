**Leia e compreenda os 12 Fatores (12-Factor App) e identifique quais deles a aplicação já atende e quais precisariam de ajustes para um ambiente de produção mais robusto.**

Antes de analisarmos quais os pontos dos 12-Factor App nossa aplicação está contemplando, vamos entender melhor o que são eles para que servem. Segundo The twelve-Factor App, 

"A aplicação doze-fatores é uma metodologia para construir softwares-como-serviço que:
* Usam formatos declarativos para automatizar a configuração inicial, minimizar tempo e custo para novos desenvolvedores participarem do projeto;
* Tem um contrato claro com o sistema operacional que o suporta, oferecendo portabilidade máxima entre ambientes que o executem;
* São adequados para implantação em modernas plataformas em nuvem, evitando a necessidade por servidores e administração do sistema;
* Minimizam a divergência entre desenvolvimento e produção, permitindo a implantação contínua para máxima agilidade;
* E podem escalar sem significativas mudanças em ferramentas, arquiteturas, ou práticas de desenvolvimento."v

Sendo eles 
1. Codebase: Uma base de código com rastreamento utilizando controle de revisão, muitos deploys;
2. Dependencies: Declare e isole as dependências;
3. Config: Armazene as configurações no ambiente;
4. Backing Services: Trate serviços externos como recursos anexados. Banco de dados, cache, filas → são "recursos plugáveis";
5. Build, Release, Run: Separe as etapas de build, release e execução;
6. Processes: Execute a aplicação como processos stateless. Não guarde estado na memória ou disco local;
7. Port Binding: Exponha serviços via port binding;
8. Concurrency: Escale através de múltiplos processos;
9. Disposability: Processos podem iniciar/parar rapidamente;
10. Dev/Prod Parity: Mantenha dev, staging e prod similares;
11. Logs: Trate logs como fluxos de eventos;
12. Admin Processes: Executar tarefas de administração/gerenciamento como processos pontuais;

Com base nestes fatores, pode-se apontar quais fatores o projeto, disponivel em https://github.com/dougls/toggle-master-monolith, segue dentro da desta metodologia:

| FATOR | STATUS | JUSTIFICATIVA |
|-------|--------|---------------|
| Codebase | Atende | Um repositório Git, possibilitando rastreabilidade. |
| Dependencies | Atende | As dependências estão em um arquivo aparte, requirements.txt. Sendo declaradas as versões exatas de cada dependência. |
| Config | Atende | As credenciais não estão no código. Usa variáveis de ambiente para configuração (DB_HOST, DB_NAME, etc.) |
| Backing Services | Atende | Usa o Banco PostgreSQL como serviço anexado via configuração |
| Build, Release, Run | Não Atende | Mesmo com Dockerfile que ajuda na etapa de build, não há versionamento de release e separação clara entre build e release |
| Processes | Atende | A aplicação não guarda dados na memória, todos os dados ficam em banco, se reiniciar a aplicação, não se perde nada |
| Port Binding | Atende Parcialmente | A porta 5000 está fixa no código, não pode mudar a porta sem alterar o código, deveria ser uma variável de ambiente PORT. Mas como será rodado em Docker, a configuração permite rodar em outra porta. Ex: docker run -p 8080:5000 togglemaster |
| Concurrency | Atende | Rodando em docker atende, pois usa o gunicorn para rodar vários workers. |
| Disposability | Atende Parcialmente | A aplicação inicia rapidamente e ao encerrar, o Gunicorn faz graceful shutdown básico, aguardando um breve período para que possíveis requisições terminem |
| Dev/Prod Parity | Atende | Mesmo o ambiente de Dev e Prod serem diferentes, já que um roda local e outro dentro da AWS, pois irá rodar dentro de um docker, assim criando condições iguais para ambos os ambientes. |
| Logs | Atende | Os logs são tratados e aparecem no terminal, podendo ser capturados e enviados para ferramentas de análise externas |
| Admin Processes | Atende Parcialmente | Tem comandos CLI como por exemplo, para inicializar banco com flask init-db. Mas não tem um sistema de migrations |

The twelve-Factor App. Disponível em: https://12factor.net/pt_br/
