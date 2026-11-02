# Metrics Server

Metrics Server `0.9.0` se instala con el chart oficial `3.14.0`. Esa versión soporta Kubernetes
`1.34` o superior. El argumento `--kubelet-insecure-tls` se limita a Minikube, cuyos certificados
de kubelet no contienen una CA verificable por Metrics Server; no debe trasladarse a producción.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version 3.14.0 \
  --namespace kube-system \
  --values kubernetes/platform/metrics-server/values.yaml \
  --wait \
  --timeout 5m
```
