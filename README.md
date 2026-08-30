# Desafio Técnico - Analista de Infraestrutura / DevOps (ESIG Group)

> **Nota:**
> Aqui ficam as explicações, decisões e o histórico de dificuldades; para o
> código, os links abaixo apontam direto para os arquivos reais.

Esse repositório contém a solução do desafio técnico enviado pela ESIG Group:
configurar um servidor Jenkins atualizado, rodando primeiro em Docker e depois
em Kubernetes, com métricas expostas via Jolokia e coletadas pelo Prometheus
(junto com o Node Exporter, para métricas do próprio nó do cluster).

Abaixo documento tudo, do ambiente até a execução, seguindo a mesma ordem das
etapas pedidas no desafio, além das dificuldades encontradas pelo caminho.

---

## Ambiente utilizado

O desenvolvimento todo foi feito dentro de uma máquina virtual Ubuntu, criada
no **Oracle VirtualBox**, rodando num host Windows.

**Especificações da VM:**
- Sistema: Ubuntu (desktop)
- RAM: 7046 MB (~7 GB)
- vCPUs: 6
- Disco: 60GB (arquivo `Ubuntu.vdi`, controladora SATA)

### Ferramentas instaladas/configuradas na VM

Além do Docker, Minikube, kubectl e VS Codium (já usados como base de
trabalho), alguns ajustes específicos foram feitos:

- **Servidor SSH**, para permitir transferir os arquivos do projeto direto do
  Windows para a VM via `scp`:
  ```bash
  sudo apt update && sudo apt install -y openssh-server && sudo systemctl start ssh
  ```

- **Permissão de Docker para o usuário comum** (sem isso, todo comando
  `docker` precisaria de `sudo`):
  ```bash
  sudo usermod -aG docker user
  newgrp docker
  ```

- **VirtualBox Guest Additions**, para habilitar recursos de integração com o
  host, como área de transferência (clipboard) compartilhada e
  arrastar-e-soltar de arquivos entre Windows e a VM:
  ```bash
  sudo apt install -y virtualbox-guest-utils virtualbox-guest-x11
  ```

### Versões confirmadas no ambiente final

| Ferramenta | Versão |
|---|---|
| Docker | 29.7.2 |
| Minikube | v1.38.1 |
| kubectl | v1.37.0 |
| VS Codium | 1.105.17075 |

---

## Como está organizado o projeto

```
desafio-esig-devops/
├── docker/
│   ├── Dockerfile
│   └── jmx-exporter/
│       └── config.yml
├── k8s/
│   ├── deployment.yaml
│   └── service.yaml
├── monitoring/
│   ├── prometheus-config.yaml
│   ├── prometheus-deployment.yaml
│   └── node-exporter.yaml
├── .gitignore
├── LICENSE
└── README.md
```

---

## Etapa 1: Docker

**Tarefa pedida:** criar um contêiner com o Jenkins rodando em um servidor de
aplicação (JBoss ou Tomcat), com métricas expostas via Jolokia.

### O que foi feito

O Jenkins foi colocado para rodar sobre uma imagem base do **Tomcat**
(`tomcat:9.0-jdk17-temurin-jammy`). O código completo está em
[`docker/Dockerfile`](docker/Dockerfile). Resumo do que ele faz:

1. Baixa o `.war` oficial do Jenkins (versão 2.440.3) direto do site oficial,
   e o coloca como `ROOT.war`, para que o Jenkins responda direto na raiz do
   Tomcat (`/`), sem precisar de um caminho extra na URL.
2. Baixa o **agente Jolokia** (`jolokia-jvm-1.6.2-agent.jar`), que expõe as
   métricas internas da JVM (memória, threads, etc.) através de um endpoint
   HTTP simples.
3. Baixa também o **JMX Exporter** (`jmx_prometheus_javaagent-0.20.0.jar`) —
   o motivo dele existir é explicado com calma na Etapa 3, porque só faz
   sentido depois de entender o problema que ele resolve.
4. Copia o arquivo [`docker/jmx-exporter/config.yml`](docker/jmx-exporter/config.yml),
   que diz ao JMX Exporter quais métricas capturar (a regra usada, `.*`,
   significa "captura tudo").

O ponto-chave do Dockerfile é a linha que liga os dois agentes Java na JVM
do Tomcat/Jenkins:
```dockerfile
ENV CATALINA_OPTS="... -javaagent:.../jolokia-agent.jar=port=8778,host=0.0.0.0 -javaagent:.../jmx_prometheus_javaagent.jar=9404:.../jmx-exporter-config.yml"
```
É essa linha que faz o Jenkins expor tanto o Jolokia (porta 8778) quanto as
métricas em formato Prometheus (porta 9404) — o "porquê" dos dois juntos
está detalhado na Etapa 3.

### Antes de buildar: verificando o ambiente

Antes de rodar o build, vale confirmar que as ferramentas necessárias estão
instaladas e no estado certo. Isso evita perder tempo debugando um erro que
na verdade é só uma ferramenta parada ou um terminal apontando pro lugar
errado.

```bash
# 1. Confirma se o Docker está instalado
docker --version

# 2. Confirma se o daemon do Docker está rodando de fato
# (se der erro "Cannot connect to the Docker daemon", rode: sudo systemctl start docker)
docker info

# 3. Lista containers ativos (não pode dar erro de conexão, mesmo que venha vazio)
docker ps

# 4. Confirma se o terminal está "preso" apontando pro Docker do Minikube
# (se este comando retornar algo tipo DOCKER_HOST=tcp://192.168.49.2:...,
# rode o comando da linha 5 antes de seguir)
env | grep DOCKER_HOST

# 5. Só rode esta linha SE a linha 4 retornou algum valor
# (isso devolve o terminal pro Docker normal da VM/host)
eval $(minikube docker-env -u)
```

> **Por que o passo 4 importa:** se `eval $(minikube docker-env)` tiver sido
> rodado antes (por exemplo, ao seguir a Etapa 2 primeiro) e o terminal não
> for reiniciado, o `docker build`/`docker run` seguinte constrói e sobe o
> container **dentro do Docker do Minikube**, não no Docker da VM/host. O
> build funciona normalmente e nenhum erro aparece — mas o container fica
> "escondido" lá dentro, as portas `-p 8080:8080` etc. não chegam até a
> máquina, e `localhost:8080` simplesmente não responde nada. `docker ps`
> depois do build serve como confirmação: se o container que você acabou de
> subir não aparecer na lista, é sinal de que ele foi parar no lugar errado.

### Para buildar e testar isoladamente no Docker

```bash
cd docker
docker build -t jenkins-jolokia:v4 .
docker run -d -p 8080:8080 -p 8778:8778 -p 9404:9404 jenkins-jolokia:v4
docker ps
```

Confirme na saída do `docker ps` que o container aparece com status `Up` e
as três portas mapeadas (`0.0.0.0:8080->8080/tcp` etc.).

Acessando `http://localhost:8080`, o Jenkins pede uma senha inicial, que fica
em `/var/jenkins_home/secrets/initialAdminPassword` dentro do container.
Para pegar essa senha:

```bash
docker exec -it $(docker ps -q --filter ancestor=jenkins-jolokia:v4) cat /var/jenkins_home/secrets/initialAdminPassword
```

Testando o Jolokia:
```
http://localhost:8778/jolokia/
```

> **Testando a partir de uma VM (VirtualBox, VMware etc.):** se o navegador
> estiver rodando *fora* da VM (por exemplo, no host Windows), `localhost`
> se refere ao host, não à VM — e o link não vai abrir. Descubra o IP da VM
> com `ip a` (interface de rede, ex. `enp0s3`) e use esse IP no lugar de
> `localhost`:
> ```
> http://<IP-da-VM>:8080
> http://<IP-da-VM>:8778/jolokia/
> ```

---

## Etapa 2: Kubernetes

**Tarefa pedida:** executar a mesma aplicação da Etapa 1 dentro de um cluster
Kubernetes, com manifestos de Deployment e Service.

### O que foi feito

Foi usado o **Minikube** como cluster local. Os manifestos ficam em `k8s/`:
[`deployment.yaml`](k8s/deployment.yaml) e [`service.yaml`](k8s/service.yaml).

#### Antes de aplicar os manifestos: confirmando o cluster

O Minikube não fica rodando sozinho depois que a VM é reiniciada — ele
precisa ser subido de novo manualmente a cada nova sessão. Vale confirmar
isso antes de aplicar qualquer manifesto:

```bash
# 1. Confirma se o Minikube está instalado
minikube version

# 2. Confirma se o cluster está de pé
# (precisa mostrar host / kubelet / apiserver / kubeconfig como Running;
# se aparecer "Stopped" em qualquer um, o cluster precisa ser (re)iniciado)
minikube status

# 3. Se estiver parado, sobe o cluster
minikube start --driver=docker

# 4. Confirma se o kubectl está instalado
kubectl version --client

# 5. Confirma se o kubectl está conversando com o cluster certo
kubectl cluster-info

# 6. Confirma qual contexto está ativo (precisa ser "minikube")
kubectl config current-context
```

> Se `kubectl cluster-info` retornar algo como
> `Unable to connect to the server: dial tcp ...: connect: no route to host`,
> é sinal de que o cluster está parado (passo 2) — normalmente resolve
> rodando o `minikube start` do passo 3.

O [`deployment.yaml`](k8s/deployment.yaml) sobe 1 réplica do container
buildado na Etapa 1, expondo as três portas (8080, 8778, 9404) e com
`resources.requests/limits` definidos (512Mi/250m de request, 1024Mi/500m de
limite).

O [`service.yaml`](k8s/service.yaml) expõe as três portas via `NodePort`:

| Porta interna | Serve para | NodePort |
|---|---|---|
| 8080 | Interface do Jenkins | 30080 |
| 8778 | Jolokia (JSON, debug manual) | 30779 |
| 9404 | Métricas no formato Prometheus | 30904 |

### Subindo o cluster e aplicando os manifestos

```bash
minikube start --driver=docker
eval $(minikube docker-env)

cd docker
docker build -t jenkins-jolokia:v4 .
cd ..

kubectl apply -f k8s/
```

> Se a imagem não tiver sido buildada com o `eval $(minikube docker-env)`
> ativo antes, ela precisa ser carregada manualmente:
> ```bash
> docker save jenkins-jolokia:v4 -o jenkins-jolokia-v4.tar
> minikube image load jenkins-jolokia-v4.tar
> ```

---

## Etapa 3: Monitoramento (Prometheus + Node Exporter)

**Tarefa pedida:** configurar o Prometheus para coletar métricas via endpoint
Jolokia, e implantar o Node Exporter para métricas do nó.

### O que foi implantado

Os manifests completos estão em `monitoring/`:
[`node-exporter.yaml`](monitoring/node-exporter.yaml) (DaemonSet + Service,
imagem `prom/node-exporter:v1.7.0`),
[`prometheus-deployment.yaml`](monitoring/prometheus-deployment.yaml)
(Deployment + Service, imagem `prom/prometheus:v2.45.0`, exposto via NodePort
`30090`) e [`prometheus-config.yaml`](monitoring/prometheus-config.yaml), o
ConfigMap com a configuração final de scrape:

```yaml
scrape_configs:
  - job_name: 'jolokia'
    static_configs:
      - targets: ['jenkins-jolokia-service:9404']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter-service:9100']
```

Aplicando:
```bash
kubectl apply -f monitoring/
kubectl rollout restart deployment prometheus
```

Confirmando que os dois alvos estão "UP":
```
http://<IP-do-minikube>:30090/targets
```

### Um ponto importante e honesto: sobre "coletar via endpoint Jolokia"

O desafio pede especificamente para configurar o Prometheus "utilizando o
endpoint Jolokia". Vale registrar com transparência: **o Prometheus, na
configuração final, não bate diretamente na porta do Jolokia (8778)** — ele
bate em uma segunda porta (9404, do JMX Exporter). Explico o motivo:

O Jolokia devolve os dados em **JSON** (formato usado por várias ferramentas
de monitoramento, mas não pelo Prometheus). O Prometheus só sabe interpretar
seu próprio formato de texto (linhas tipo `nome_da_metrica valor`). Ao
apontar o Prometheus direto para `jenkins-jolokia-service:8778/jolokia/`, o
scrape falha com o erro:

```
expected a valid start token, got "{" ("INVALID") while parsing: "{"
```

Isso não é um erro de configuração — é uma incompatibilidade real de
formato entre as duas ferramentas.

**A solução adotada** foi adicionar um segundo agente Java na mesma JVM do
Jenkins: o **JMX Exporter**, da própria comunidade do Prometheus. Ele lê os
mesmos dados internos da JVM que o Jolokia lê (via JMX local), só que já
devolve tudo no formato de texto que o Prometheus entende, na porta `9404`.

Ou seja, hoje o Jenkins expõe as métricas de duas formas ao mesmo tempo:
- Porta `8778` → Jolokia, formato JSON, mantido ativo para debug manual.
- Porta `9404` → JMX Exporter, formato Prometheus, é essa que o Prometheus
  de fato usa.

#### Outras tentativas feitas antes de chegar nessa solução

Antes de adicionar o JMX Exporter como agente na própria JVM, outras
abordagens foram tentadas para tentar preservar o uso direto do Jolokia:

1. **Mudar o `metrics_path`** do job (`/`, `/metrics`,
   `/jolokia/version`, `/jolokia/read/java.lang:type=Memory`) — não resolve,
   porque o problema é o formato da resposta, não o caminho da URL.
2. **Rodar um exporter comunitário como container separado**, apontando para
   o Jolokia por rede (`v503/jolokia-exporter`, depois
   `sschepens/jolokia-exporter`) — nenhum dos dois subiu de forma estável no
   cluster.
3. **Usar a imagem oficial `prom/jmx-exporter` como container separado**,
   tentando conectar remotamente via JMX — essa via exigiria expor JMX
   remoto (RMI) na JVM do Jenkins, configuração adicional que não estava
   pronta.

A solução final evitou esses problemas ao rodar o tradutor **dentro da
mesma JVM** do Jenkins, como um segundo `-javaagent`, sem depender de rede
nem de configuração remota.

---

## Boas práticas de segurança - observações e decisões

- **Acesso anônimo de leitura no Jenkins**: por padrão, o Jenkins bloqueia
  até requisições de leitura sem autenticação (erro 403 no scrape do
  Jolokia/Jenkins). Para viabilizar o ambiente de avaliação, foi habilitado
  o acesso anônimo de leitura em *Manage Jenkins → Security*. **Em produção,
  o correto seria usar um usuário/token dedicado com `basic_auth` no
  Prometheus**, em vez de liberar leitura anônima.
- O Jolokia permanece acessível na porta 8778 sem autenticação adicional —
  aceitável em ambiente de avaliação isolado, mas em produção valeria
  restringir por rede (NetworkPolicy) ou autenticação própria do Jolokia
  (`jolokia-access.xml`).

---

## Outras dificuldades encontradas

- **Perda de configuração do Jenkins após restart do pod**: o `Deployment`
  do Jenkins não tem volume persistente (`PersistentVolumeClaim`). Sempre
  que o pod reinicia, o Jenkins volta para a tela de instalação do zero.
  Fica como melhoria futura: adicionar um `PersistentVolumeClaim` apontando
  para `/var/jenkins_home`.
- **Instabilidade momentânea do cluster local**: em um dado momento, o
  Minikube reiniciou sozinho, derrubando temporariamente o DNS interno
  (CoreDNS) e causando erros de resolução de nome entre serviços
  (`server misbehaving`). Se resolveu sozinho após o cluster estabilizar —
  reflexo de rodar tudo localmente numa única VM, sem redundância.

---

## Como rodar do zero

Existem dois caminhos possíveis, cobrindo as Etapas 1 e 2/3 do desafio. O
caminho do Kubernetes é o entregável final; o teste isolado no Docker é
opcional, mas recomendado como primeiro sanity-check antes de ir para o
cluster — ele confirma que a imagem builda e sobe corretamente, isolando
qualquer problema de Kubernetes/rede do problema da imagem em si.

### Caminho A (opcional): testar isolado no Docker primeiro

```bash
# 1. Clonar o repositório
git clone https://github.com/fernandobsouza-devops/desafio-esig-devops.git
cd desafio-esig-devops

# 2. Buildar a imagem
cd docker
docker build -t jenkins-jolokia:v4 .

# 3. Subir o container mapeando as 3 portas (Jenkins, Jolokia, métricas Prometheus)
docker run -d -p 8080:8080 -p 8778:8778 -p 9404:9404 jenkins-jolokia:v4

# 4. Confirmar que subiu e as portas estão mapeadas
docker ps

# 5. Voltar para a raiz do projeto antes do Caminho B
cd ..
```

Pegar a senha inicial do Jenkins nesse container:
```bash
docker exec -it $(docker ps -q --filter ancestor=jenkins-jolokia:v4) cat /var/jenkins_home/secrets/initialAdminPassword
```

Acessar (troque por `http://<IP-da-VM>:8080` se estiver testando de fora da VM):
- Jenkins: `http://localhost:8080`
- Jolokia (debug manual): `http://localhost:8778/jolokia/`

> Esse container isolado não interfere no Caminho B — são ambientes
> independentes. Você pode derrubá-lo depois (`docker rm -f $(docker ps -q
> --filter ancestor=jenkins-jolokia:v4)`) ou deixá-lo rodando, sem conflito
> com o cluster Kubernetes.

### Caminho B: implantação completa no Kubernetes (entregável final)

```bash
# 1. Clonar o repositório (pule se já fez no Caminho A)
git clone https://github.com/fernandobsouza-devops/desafio-esig-devops.git
cd desafio-esig-devops

# 2. Subir o Minikube
minikube start --driver=docker
eval $(minikube docker-env)

# 3. Buildar a imagem do Jenkins
# (precisa ser buildada de novo aqui, dentro do docker-env do Minikube —
# a imagem buildada no Caminho A fica no Docker da VM, não no do cluster)
cd docker
docker build -t jenkins-jolokia:v4 .
cd ..

# 4. Aplicar os manifestos
kubectl apply -f k8s/
kubectl apply -f monitoring/

# 5. Acompanhar a subida dos pods
kubectl get pods -w
```

Pegar a senha inicial do Jenkins nesse ambiente:
```bash
kubectl exec -it $(kubectl get pods -l app=jenkins-jolokia -o jsonpath="{.items[0].metadata.name}") -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Acessar tudo:
```bash
minikube ip
```
- Jenkins: `http://<IP-do-minikube>:30080`
- Prometheus: `http://<IP-do-minikube>:30090`
- Jolokia (debug manual): `http://<IP-do-minikube>:30779/jolokia/`

---

## Retomando um ambiente já existente (depois de desligar a VM/PC)

O cenário acima ("Como rodar do zero") serve para a primeira vez. Mas se o
projeto já foi implantado antes e a VM foi desligada ou reiniciada nesse
meio tempo, o Minikube **não volta sozinho** — ele precisa ser levantado de
novo, mesmo que os manifestos já tenham sido aplicados anteriormente. A boa
notícia é que os pods, deployments e services continuam configurados: não
é necessário rodar `kubectl apply` de novo, só religar o cluster.

```bash
# 1. Confirma o estado atual do cluster
# (se aparecer "Stopped" em host/kubelet/apiserver, ele precisa ser religado)
minikube status

# 2. Religa o cluster (idempotente: se já estiver rodando, só confirma)
minikube start --driver=docker

# 3. Confirma de novo que subiu tudo (host/kubelet/apiserver Running)
minikube status

# 4. Confirma que o kubectl está conversando com o cluster
kubectl cluster-info

# 5. Confirma que os pods do projeto voltaram sozinhos (sem precisar reaplicar nada)
kubectl get pods -A
```

> É normal, depois de religar, o campo `RESTARTS` desses pods aparecer
> incrementado (ex. `2`) — isso reflete o próprio Minikube reiniciando o
> container do node, não um erro na aplicação. O importante é o `STATUS`
> aparecer como `Running` e o `READY` como `1/1`.

Com o cluster de volta, confirme os endereços de acesso (o IP pode mudar
entre sessões, então vale conferir de novo):

```bash
# Pega o IP atual do node do Minikube
minikube ip

# Confirma que os services continuam expostos nas mesmas portas
kubectl get svc -n default
```

Acesse (trocando `<IP>` pelo que o `minikube ip` retornou):
- Jenkins: `http://<IP>:30080`
- Prometheus (confirme `jolokia` e `node-exporter` como **UP**): `http://<IP>:30090/targets`
- Jolokia bruto (debug manual): `http://<IP>:30779/jolokia/`

Se algum desses não abrir, ou o `kubectl cluster-info` retornar erro de
conexão (`no route to host` ou similar), volte ao passo 2 e confirme se o
`minikube start` terminou sem erros antes de tentar de novo.

---

## Troubleshooting: pegando a senha inicial do Jenkins (Docker e Kubernetes)

Os ambientes de Docker isolado (Etapa 1) e Kubernetes (Etapa 2/3) rodam
containers/pods **completamente independentes** — cada um tem seu próprio
Jenkins, seu próprio `JENKINS_HOME` e, portanto, sua própria senha inicial.
Testar a senha de um não serve para o outro.

**No Docker isolado:**
```bash
docker exec -it $(docker ps -q --filter ancestor=jenkins-jolokia:v4) cat /var/jenkins_home/secrets/initialAdminPassword
```

**No Kubernetes:**
```bash
kubectl exec -it $(kubectl get pods -l app=jenkins-jolokia -o jsonpath="{.items[0].metadata.name}") -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Use a senha retornada por cada comando no `http://localhost:8080` (Docker)
ou `http://<IP-do-minikube>:30080` (Kubernetes) correspondente.

### Se o comando retornar "No such file or directory"

Isso **não é um erro** — é o comportamento esperado do Jenkins depois que o
wizard inicial já foi concluído em algum momento anterior naquele mesmo
container/pod. Por segurança, o Jenkins apaga o arquivo
`initialAdminPassword` assim que a instalação é finalizada (usuário/senha
definidos manualmente na interface).

Nesse caso, faça login direto com o usuário/senha que foram definidos
durante aquele wizard, em vez de tentar usar a senha inicial. Para
confirmar se existe um usuário já configurado:

```bash
# No Docker isolado
docker exec -it $(docker ps -q --filter ancestor=jenkins-jolokia:v4) ls /var/jenkins_home/users/

# No Kubernetes
kubectl exec -it $(kubectl get pods -l app=jenkins-jolokia -o jsonpath="{.items[0].metadata.name}") -- ls /var/jenkins_home/users/
```

Se você não lembra qual usuário/senha foi definido, a saída mais simples é
recriar o Jenkins do zero naquele ambiente (como não há
`PersistentVolumeClaim` configurado, o dado não é persistido de propósito
— ver seção "Outras dificuldades encontradas"):

```bash
# No Docker isolado: remove o container e sobe um novo
docker rm -f $(docker ps -q --filter ancestor=jenkins-jolokia:v4)
docker run -d -p 8080:8080 -p 8778:8778 -p 9404:9404 jenkins-jolokia:v4

# No Kubernetes: mata o pod, o Deployment sobe um novo automaticamente
kubectl delete pod -l app=jenkins-jolokia
```

Depois disso, o arquivo `initialAdminPassword` volta a existir e os
comandos originais funcionam de novo.

---

## Sugestões de próximos passos

- Adicionar `PersistentVolumeClaim` para o Jenkins não perder dados entre
  restarts.
- Trocar o acesso anônimo de leitura por autenticação via API Token.
- Subir Grafana (sugerido no desafio) usando o Prometheus já configurado
  aqui como fonte de dados.

---

## Uso de IA

Durante o desenvolvimento, foi usada IA (Claude) como apoio para:
- Diagnosticar os erros que apareciam no Prometheus (403, erro de DNS, erro
  de parsing do JSON vindo do Jolokia).
- Entender a diferença entre Jolokia e JMX Exporter, e por que os dois eram
  necessários juntos para viabilizar a coleta de métricas.
- Revisar os manifests do Kubernetes e a estrutura do repositório.

As decisões finais e os testes em cada etapa foram feitos manualmente,
conferindo o resultado real no ambiente antes de seguir para o próximo
passo.