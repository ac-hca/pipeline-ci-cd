# Kubernetes para TaskFlow API

Esta etapa despliega TaskFlow API y PostgreSQL en el clúster Minikube local creado por
Terraform. Terraform administra solamente el clúster; Kustomize y kubectl administran los
recursos de la aplicación. El overlay `production` es una configuración de referencia que se
renderiza y valida, pero no representa una plataforma productiva real.

## Arquitectura

```text
Cliente local
  `-- taskflow.local
        `-- F5 NGINX Ingress Controller
              `-- Service taskflow-api:80
                    `-- Deployment taskflow-api:8000
                          `-- Service taskflow-postgres:5432
                                `-- StatefulSet + PVC taskflow-postgres

Metrics Server --> HPA taskflow-api --> Deployment taskflow-api
Job taskflow-migrate --> alembic upgrade head --> PostgreSQL
```

El despliegue también incluye:

- un Namespace con el perfil Pod Security `restricted` por entorno;
- un ServiceAccount sin montaje automático del token de Kubernetes;
- un ConfigMap generado con valores no sensibles;
- un Secret generado localmente desde un archivo ignorado por Git;
- NetworkPolicies para limitar el tráfico entre Ingress, API, migraciones, PostgreSQL y DNS;
- probes de inicio, vida y disponibilidad;
- requests, limits, HPA y PodDisruptionBudget;
- almacenamiento persistente dinámico para PostgreSQL.

## Organización de los manifiestos

```text
kubernetes/
|-- base/                       Recursos comunes sin namespace fijo
|-- overlays/
|   |-- development/            Minikube local, imagen cargada y recursos reducidos
|   `-- production/             Referencia renderizable, no desplegada en esta etapa
`-- platform/
    |-- nginx-ingress/          Valores del controlador de Ingress
    `-- metrics-server/         Valores para métricas en Minikube
```

La base contiene el modelo común. Cada overlay agrega su Namespace, ConfigMap, Secret, imagen y
parches de capacidad. Kustomize añade un hash al nombre del ConfigMap y del Secret; un cambio de
configuración actualiza automáticamente sus referencias y provoca un rollout controlado.

| Diferencia | Development | Production de referencia |
|---|---|---|
| Namespace | `taskflow-development` | `taskflow-production` |
| Réplicas iniciales de API | 1 | 2 |
| Imagen | `taskflow-api:k8s-dev`, local | GHCR con etiqueta `sha-*` |
| Política de descarga | `Never` | `IfNotPresent` |
| HPA | 1 a 3 réplicas, CPU 70 % | 2 a 6 réplicas, CPU 65 % |
| PDB | `maxUnavailable: 1` | `minAvailable: 1` |
| PVC PostgreSQL | 2 GiB | 10 GiB |
| Host de Ingress | `taskflow.local` | `taskflow.example.invalid` |

La ruta real de tareas definida por la aplicación es `/api/v1/tasks`; por eso el Ingress publica
esa ruta, además de `/health/live`, `/health/ready`, `/docs` y `/`.

## Versiones fijadas

| Componente | Versión |
|---|---:|
| Kubernetes y kubectl | `v1.37.0` |
| Minikube | `1.39.0` |
| Terraform | `1.16.7` |
| Helm | `4.3.1` |
| F5 NGINX Ingress Controller | `5.7.0` |
| Chart F5 NGINX Ingress | `2.8.0` |
| Metrics Server | `0.9.0` |
| Chart Metrics Server | `3.14.0` |
| PostgreSQL | `16.15-alpine3.24` |
| Kubeconform | `0.8.0` |
| Checkov | `3.3.29` |

El proyecto comunitario `kubernetes/ingress-nginx` fue retirado en marzo de 2026 y ya no recibe
correcciones. Por esa razón se utiliza el controlador mantenido por F5, cuya versión `5.7.0`
declara compatibilidad con Kubernetes `1.30` a `1.37` y publica imágenes AMD64 y ARM64. No se
utiliza el addon de Ingress de Minikube.

## Prerrequisitos

- Docker Desktop iniciado y con al menos 4 CPU y 6 GiB de RAM disponibles.
- Terraform `1.16.7`.
- Minikube CLI `1.39.0`.
- kubectl `v1.37.0`.
- Helm `4.3.1`.
- Acceso a Internet para descargar imágenes, charts y providers durante la primera ejecución.

Comprobar las herramientas desde la raíz del repositorio:

```bash
docker info
terraform version
minikube version
kubectl version --client
helm version
```

## 1. Crear el clúster

```bash
cd terraform/environments/development
terraform init -backend=false -input=false
terraform validate
terraform plan -input=false -out=taskflow-development.tfplan
terraform apply -input=false taskflow-development.tfplan
cd ../../..
```

Usar siempre el contexto explícito para evitar operar sobre otro clúster:

```bash
kubectl --context taskflow-development get nodes -o wide
minikube status --profile taskflow-development
```

El nodo debe aparecer `Ready` con Kubernetes `v1.37.0`.

## 2. Instalar Ingress y Metrics Server

Instalar el controlador de Ingress con los valores versionados:

```bash
helm upgrade --install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress \
  --version 2.8.0 \
  --namespace nginx-ingress \
  --create-namespace \
  --values kubernetes/platform/nginx-ingress/values.yaml \
  --kube-context taskflow-development \
  --wait \
  --timeout 5m
```

Instalar Metrics Server:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version 3.14.0 \
  --namespace kube-system \
  --values kubernetes/platform/metrics-server/values.yaml \
  --kube-context taskflow-development \
  --wait \
  --timeout 5m
```

El argumento `--kubelet-insecure-tls` está limitado al archivo de valores de Minikube porque sus
certificados de kubelet no presentan una cadena verificable por Metrics Server. No debe copiarse a
un clúster productivo.

Comprobar ambos componentes:

```bash
kubectl --context taskflow-development get pods -n nginx-ingress
kubectl --context taskflow-development get deployment metrics-server -n kube-system
kubectl --context taskflow-development get apiservice v1beta1.metrics.k8s.io
```

## 3. Construir y cargar la imagen local

El overlay de desarrollo no depende de GHCR. Construir la etapa runtime para la arquitectura de la
máquina y cargarla en el runtime de Minikube:

```bash
docker build \
  --target runtime \
  --tag taskflow-api:k8s-dev \
  --file docker/Dockerfile \
  .

minikube image load taskflow-api:k8s-dev --profile taskflow-development
minikube image ls --profile taskflow-development | grep taskflow-api
```

`imagePullPolicy: Never` evita que Kubernetes intente descargar esa etiqueta local.

## 4. Crear los secretos de desarrollo

Copiar solamente la plantilla y reemplazar todos los valores `CHANGE_ME` de manera local:

```bash
cp kubernetes/overlays/development/secrets.env.example \
  kubernetes/overlays/development/secrets.env
```

Los cuatro valores deben ser coherentes entre sí:

```text
POSTGRES_DB=taskflow
POSTGRES_USER=taskflow
POSTGRES_PASSWORD=<contraseña-local-aleatoria>
DATABASE_URL=postgresql+psycopg://taskflow:<misma-contraseña>@taskflow-postgres:5432/taskflow
```

`secrets.env` está ignorado por Git. Kustomize lo transforma en un Secret al renderizar o aplicar
el overlay. El Secret se monta como archivos de solo lectura; las credenciales no se imprimen en
el manifiesto versionado ni se guardan como variables visibles en la especificación del Pod.

Antes de continuar, comprobar que el archivo real no está versionado:

```bash
git check-ignore kubernetes/overlays/development/secrets.env
git ls-files kubernetes/overlays/development/secrets.env
```

El primer comando debe mostrar la ruta y el segundo no debe producir salida.

## 5. Renderizar y validar

Kustomize necesita un archivo `secrets.env` local en cada overlay. Para validar producción sin
usar credenciales reales se puede copiar temporalmente su plantilla:

```bash
cp kubernetes/overlays/production/secrets.env.example \
  kubernetes/overlays/production/secrets.env

kubectl kustomize kubernetes/overlays/development >/tmp/taskflow-development.yaml
kubectl kustomize kubernetes/overlays/production >/tmp/taskflow-production.yaml
```

No guardar esos manifiestos renderizados en el repositorio: contienen datos codificados del
Secret de validación. El workflow los escribe en `RUNNER_TEMP`, ejecuta Kubeconform `0.8.0` en
modo estricto y analiza el resultado con Checkov `3.3.29`.

Al terminar una validación manual:

```bash
rm /tmp/taskflow-development.yaml /tmp/taskflow-production.yaml
rm kubernetes/overlays/production/secrets.env
```

## 6. Desplegar desarrollo y ejecutar las migraciones

Aplicar el overlay completo:

```bash
kubectl --context taskflow-development apply \
  -k kubernetes/overlays/development
```

Kubernetes recibe todos los objetos juntos, pero el orden efectivo está protegido:

1. PostgreSQL inicia y su readiness usa `pg_isready`.
2. El init container del Job espera una conexión real con PostgreSQL.
3. El contenedor principal del Job ejecuta una sola vez `alembic upgrade head`.
4. El init container del Deployment espera que Alembic confirme todos los heads actuales.
5. Uvicorn inicia y la readiness de la API comprueba PostgreSQL.

Así, las réplicas de la API nunca ejecutan migraciones concurrentes. Esperar explícitamente los
recursos:

```bash
kubectl --context taskflow-development \
  -n taskflow-development rollout status statefulset/taskflow-postgres --timeout=5m

kubectl --context taskflow-development \
  -n taskflow-development wait --for=condition=complete job/taskflow-migrate --timeout=5m

kubectl --context taskflow-development \
  -n taskflow-development rollout status deployment/taskflow-api --timeout=5m
```

Si el Job falla, consultar los dos contenedores antes de recrearlo:

```bash
kubectl --context taskflow-development -n taskflow-development \
  logs job/taskflow-migrate --all-containers
```

Un Job terminado es inmutable. Después de corregir su causa, eliminar solo ese Job y volver a
aplicar el overlay:

```bash
kubectl --context taskflow-development -n taskflow-development delete job taskflow-migrate
kubectl --context taskflow-development apply -k kubernetes/overlays/development
```

## 7. Verificar Pods, Service, almacenamiento y salud

```bash
kubectl --context taskflow-development -n taskflow-development get pods -o wide
kubectl --context taskflow-development -n taskflow-development get service
kubectl --context taskflow-development -n taskflow-development get endpointslice
kubectl --context taskflow-development -n taskflow-development get pvc
kubectl --context taskflow-development -n taskflow-development get job taskflow-migrate
```

Comprobar directamente el Service desde la computadora local:

```bash
kubectl --context taskflow-development -n taskflow-development \
  port-forward service/taskflow-api 8000:80
```

En otra terminal:

```bash
curl --fail http://127.0.0.1:8000/health/live
curl --fail http://127.0.0.1:8000/health/ready
curl --fail http://127.0.0.1:8000/api/v1/tasks
```

## 8. Acceder mediante Ingress en macOS

El Service del controlador es `ClusterIP`, lo que evita depender de un LoadBalancer cloud, del
addon de Minikube o de rutas especiales de Docker Desktop. El método reproducible usado en macOS
es un port-forward:

```bash
kubectl --context taskflow-development -n nginx-ingress \
  port-forward service/nginx-ingress-controller 8080:80
```

En otra terminal, enviar el host configurado en el Ingress:

```bash
curl --fail --header 'Host: taskflow.local' \
  http://127.0.0.1:8080/health/live
curl --fail --header 'Host: taskflow.local' \
  http://127.0.0.1:8080/health/ready
curl --fail --header 'Host: taskflow.local' \
  http://127.0.0.1:8080/api/v1/tasks
curl --fail --header 'Host: taskflow.local' \
  http://127.0.0.1:8080/docs
```

También puede agregarse `127.0.0.1 taskflow.local` al archivo de hosts local y abrir
`http://taskflow.local:8080/docs`. El port-forward debe permanecer activo durante el acceso.

## 9. Verificar HPA, métricas y PDB

Metrics Server puede tardar algunos segundos en publicar la primera muestra:

```bash
kubectl --context taskflow-development top pods -n taskflow-development
kubectl --context taskflow-development get hpa -n taskflow-development
kubectl --context taskflow-development describe hpa taskflow-api -n taskflow-development
kubectl --context taskflow-development get pdb -n taskflow-development
```

El HPA escala únicamente la API y depende del request de CPU del contenedor. PostgreSQL conserva
una réplica. En un clúster de un nodo, más Pods no aportan tolerancia ante la caída del nodo; el PDB
solo limita disrupciones voluntarias y no puede crear disponibilidad física.

## 10. Comprobar idempotencia

```bash
kubectl --context taskflow-development apply \
  -k kubernetes/overlays/development

kubectl --context taskflow-development diff \
  -k kubernetes/overlays/development
```

La segunda aplicación debe resultar sin cambios relevantes. `kubectl diff` devuelve código `0`
cuando el estado declarado coincide con el clúster.

## Imagen privada de GHCR

El overlay de producción referencia una etiqueta `sha-*`, nunca `latest` ni la etiqueta móvil
`main`. Antes de usar una imagen privada se crea el pull secret en tiempo de ejecución:

```bash
kubectl --context <contexto> create namespace taskflow-production
kubectl --context <contexto> -n taskflow-production create secret docker-registry ghcr-credentials \
  --docker-server=ghcr.io \
  --docker-username=ac-hca \
  --docker-password="$GHCR_TOKEN"
```

`GHCR_TOKEN` debe tener permiso `read:packages` y permanecer fuera del repositorio y del historial
del shell. El Secret no se exporta a YAML. Antes de un despliegue futuro se debe reemplazar la
etiqueta de ejemplo en `kubernetes/overlays/production/kustomization.yaml` por la etiqueta SHA o
versión inmutable realmente publicada.

El overlay de producción se limita por ahora a:

```bash
cp kubernetes/overlays/production/secrets.env.example \
  kubernetes/overlays/production/secrets.env
kubectl kustomize kubernetes/overlays/production >/tmp/taskflow-production.yaml
rm /tmp/taskflow-production.yaml kubernetes/overlays/production/secrets.env
```

No debe aplicarse al Minikube de desarrollo como sustituto de una infraestructura productiva.

## Limpieza completa

Detener cualquier port-forward y eliminar primero la aplicación y los componentes instalados:

```bash
kubectl --context taskflow-development delete \
  -k kubernetes/overlays/development --ignore-not-found

helm uninstall nginx-ingress \
  --namespace nginx-ingress \
  --kube-context taskflow-development

helm uninstall metrics-server \
  --namespace kube-system \
  --kube-context taskflow-development

rm kubernetes/overlays/development/secrets.env
```

Destruir el clúster mediante Terraform:

```bash
cd terraform/environments/development
terraform destroy -input=false
terraform state list
cd ../../..

minikube profile list
docker ps --all --filter name=taskflow-development
```

El estado de Terraform debe quedar vacío y no deben quedar perfiles ni contenedores de Minikube.

## Seguridad aplicada

- API, init containers y Job se ejecutan sin root con UID/GID `10001`.
- PostgreSQL utiliza el UID/GID `70` propio de la imagen Alpine fijada.
- Se elimina `ALL` de capabilities y se impide la escalada de privilegios.
- Se utiliza `RuntimeDefault` como perfil seccomp y filesystem raíz de solo lectura.
- Los paths que necesitan escritura utilizan `emptyDir` con límite o el PVC.
- No se monta el token del ServiceAccount.
- PostgreSQL es un Service interno `ClusterIP` y no se publica fuera del clúster.
- Las NetworkPolicies aplican denegación implícita y habilitan solo los flujos necesarios.
- Ningún secreto, kubeconfig, estado o manifiesto renderizado se versiona.

Checkov conserva excepciones explícitas y acotadas para la imagen local sin digest, la política
`Never` de desarrollo, la etiqueta fijada de PostgreSQL y su UID requerido. No se ignoraron
hallazgos de privilegios, exposición, recursos o probes.

## Integración continua

El job `Kubernetes manifests` de `.github/workflows/ci.yml`:

1. rechaza archivos de secretos runtime versionados;
2. crea entradas de validación a partir de las plantillas;
3. renderiza ambos overlays con kubectl `v1.37.0`;
4. valida los esquemas con Kubeconform `0.8.0`;
5. analiza los manifiestos renderizados con Checkov `3.3.29`.

El job de publicación usa Buildx y QEMU para publicar un único manifest list con
`linux/amd64` y `linux/arm64`. Continúa usando el `GITHUB_TOKEN` temporal y las etiquetas
`sha-*`, `main` y `vX.Y.Z` según el evento.

No se agregó todavía una prueba de despliegue real dentro de GitHub Actions. La validación real de
esta etapa fue local; así se evita duplicar en CI un clúster costoso hasta diseñar correctamente su
cleanup incondicional. DAST, Prometheus y Grafana permanecen fuera de alcance.

## Resultado de la validación real

Prueba ejecutada el 1 de noviembre de 2026 en Apple Silicon ARM64:

| Comprobación | Resultado |
|---|---|
| Terraform apply | Clúster `taskflow-development` creado; nodo `Ready`, Kubernetes `v1.37.0`. |
| F5 NGINX | Chart `2.8.0`, controlador `5.7.0`, Pod disponible. |
| Metrics Server | Chart `3.14.0`, API de métricas `Available=True`. |
| Imagen local | Runtime ARM64 construido y cargado en Minikube. |
| PostgreSQL | `1/1 Running`; PVC de 2 GiB `Bound`. |
| Migración | Job `Complete`; Alembic aplicó `20261011_0001`. |
| API | `1/1 Running`; rollout correcto. |
| Probes | `/health/live` y `/health/ready` respondieron correctamente. |
| API y persistencia | Se creó y recuperó una tarea real a través del Ingress. |
| Ingress | Live, ready, docs y `/api/v1/tasks` respondieron por `taskflow.local`. |
| Métricas | `kubectl top` mostró API en 2 mCPU y 62 MiB. |
| HPA | Métrica `cpu: 2%/70%`, mínimo 1, máximo 3. |
| PDB | Creado y activo. |
| Idempotencia Kubernetes | Segunda aplicación y `kubectl diff` sin cambios. |
| Idempotencia Terraform | Segundo plan: `No changes`. |
| Kubeconform | 30 recursos válidos, 0 inválidos, 0 errores. |
| Checkov Kubernetes | 538 controles aprobados, 0 fallidos, 12 excepciones documentadas. |
| Build multi-arquitectura | Build OCI local AMD64/ARM64 correcto. |
| Limpieza | Aplicación y charts eliminados; Terraform destruyó el clúster. |
| Estado final | Estado Terraform vacío, 0 perfiles y 0 contenedores Minikube. |

La prueba detectó que psycopg no acepta directamente el esquema SQLAlchemy
`postgresql+psycopg://`. El init container del Job transforma únicamente ese prefijo a
`postgresql://` para realizar su conexión de espera; Alembic y la API siguen consumiendo el valor
original mediante SQLAlchemy.

## Limitaciones y trabajo posterior

- Minikube y el overlay de producción no sustituyen un clúster productivo multi-nodo.
- El PVC de PostgreSQL es persistente durante la vida del perfil, pero desaparece al destruirlo.
- No hay TLS local; el acceso reproducible usa HTTP y port-forward.
- El PDB no protege contra la pérdida del único nodo.
- El HPA escala Pods, no nodos ni PostgreSQL.
- `--kubelet-insecure-tls` es una concesión exclusiva del entorno local.
- El host, capacidad, almacenamiento, secretos y estrategia de PostgreSQL de producción requieren
  un diseño de plataforma real antes de cualquier uso productivo.
- La ejecución del workflow y la publicación efectiva en GHCR se comprobarán después de que el
  usuario realice el push.
- Prometheus, Grafana y DAST pertenecen a etapas posteriores.

## Referencias

- [Retiro de ingress-nginx](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Compatibilidad de F5 NGINX Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/changelog)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Kubeconform v0.8.0](https://github.com/yannh/kubeconform/releases/tag/v0.8.0)
