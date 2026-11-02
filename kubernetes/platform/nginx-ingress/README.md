# F5 NGINX Ingress Controller

TaskFlow utiliza el controlador mantenido por F5, no el proyecto comunitario retirado
`kubernetes/ingress-nginx`. La versión del controlador es `5.7.0` y la del chart es `2.8.0`.
Ambas arquitecturas necesarias (`linux/amd64` y `linux/arm64`) están publicadas.

Instalación con Helm `4.3.1`:

```bash
helm upgrade --install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress \
  --version 2.8.0 \
  --namespace nginx-ingress \
  --create-namespace \
  --values kubernetes/platform/nginx-ingress/values.yaml \
  --wait \
  --timeout 5m
```

El Service queda como `ClusterIP`. En macOS se accede de forma reproducible mediante
`kubectl port-forward`; no se depende de un LoadBalancer cloud ni del addon de Minikube.
