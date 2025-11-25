Leia e compreenda os 12 Fatores (12-Factor App) e identifique quais deles a aplicação já atende e quais precisariam de ajustes para um ambiente de produção mais robusto.

Antes de analisarmos quais os pontos dos 12-Factor App nossa aplicação está contemplando, vamos entender melhor o que são eles para que servem. Segundo The twelve-Factor App, 

"A aplicação doze-fatores é uma metodologia para construir softwares-como-serviço que:
* Usam formatos declarativos para automatizar a configuração inicial, minimizar tempo e custo para novos desenvolvedores participarem do projeto;
* Tem um contrato claro com o sistema operacional que o suporta, oferecendo portabilidade máxima entre ambientes que o executem;
* São adequados para implantação em modernas plataformas em nuvem, evitando a necessidade por servidores e administração do sistema;
* Minimizam a divergência entre desenvolvimento e produção, permitindo a implantação contínua para máxima agilidade;
* E podem escalar sem significativas mudanças em ferramentas, arquiteturas, ou práticas de desenvolvimento."

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
| Processes | | |
| Port Binding | | |
| Concurrency | | |
| Disposability | | |
| Dev/Prov Parity | | |
| Logs | | |
| Admin Processes | | |

The twelve-Factor App. Disponível em: https://12factor.net/pt_br/
