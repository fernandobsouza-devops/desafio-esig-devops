# Desafio Técnico - Analista de Infraestrutura e DevOps (ESIG Group)

Repositório contendo a solução para a atividade técnica de integração contínua, conteinerização, orquestração e monitoramento para o grupo ESIG.

---

## 🏗️ Estrutura do Projeto

```text
.
├── docker/
│   └── Dockerfile               # Build do Tomcat 9 + Jenkins WAR + Jolokia Agent
├── k8s/
│   ├── deployment.yaml          # Deployment da aplicação Jenkins/Jolokia
│   └── service.yaml             # Exposure do Jenkins (Porta 30080) e Jolokia (Porta 30778)
├── monitoring/
│   ├── prometheus-config.yaml   # Scrape configs do Jolokia e Node Exporter
│   ├── prometheus-deployment.yaml # Deployment e Service do Prometheus
│   └── node-exporter.yaml       # DaemonSet do Node Exporter para os nós
└── extra/
    └── README.md                # Componentes adicionais (Grafana / JBoss)