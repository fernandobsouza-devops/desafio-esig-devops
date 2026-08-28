# Etapa 2: Kubernetes

Esta pasta contém os manifestos YAML para implantação da aplicação Jenkins + Jolokia no Kubernetes.

## Deploy da Aplicação

```bash
kubectl apply -f deployment.yaml -f service.yaml
```

## Redirecionamento de Portas (Port-Forward)

```bash
kubectl port-forward svc/jenkins-jolokia-service 8080:8080 8778:8778
```

## Endpoints de Acesso
- **Jenkins Web:** http://localhost:8080
- **Métricas Jolokia:** http://localhost:8778/jolokia/

## Verificação dos Recursos
```bash
kubectl get pods,svc -l app=jenkins-jolokia
```
