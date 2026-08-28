#!/bin/bash
kubectl apply -f prometheus-config.yaml
kubectl apply -f jolokia-exporter.yaml
kubectl apply -f node-exporter.yaml
kubectl apply -f prometheus-deployment.yaml
echo "Tudo aplicado com sucesso!"
