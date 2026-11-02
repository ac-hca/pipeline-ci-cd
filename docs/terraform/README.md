# Terraform para Minikube

Terraform administra exclusivamente el ciclo de vida del clúster Minikube local y efímero de
TaskFlow. No crea Deployments, Services, Ingress, HPA, PostgreSQL, Prometheus, Grafana ni el
registry de imágenes. GHCR continúa siendo administrado fuera de Terraform.

La configuración utiliza estado local y el driver Docker. No contiene backends remotos,
credenciales cloud ni provisioners imperativos como `local-exec`.

## Arquitectura

```text
terraform/
|-- modules/
|   `-- minikube-cluster/       Módulo reutilizable del clúster
`-- environments/
    |-- development/            Root module ejecutable
    `-- production/             Reservado; no contiene infraestructura
```

El módulo `development` llama a `minikube-cluster`. El provider comunitario crea el perfil de
Minikube, espera el API server, los Pods del sistema y el nodo `Ready`, y elimina el perfil durante
`terraform destroy`.

## Versiones fijadas

| Componente | Versión | Decisión |
|---|---:|---|
| Terraform CLI | `1.16.7` | Versión exacta en `required_version` y GitHub Actions. |
| Provider `scott-the-programmer/minikube` | `0.8.0` | Versión exacta y hashes registrados en `.terraform.lock.hcl`. |
| Minikube | `1.39.0` | Versión incorporada por el provider y recomendada para la CLI de verificación. |
| Kubernetes | `v1.37.0` | Versión explícita soportada por Minikube `1.39.0`. |
| Driver | `docker` | Mismo modelo local en macOS ARM64 y en Ubuntu AMD64. |
| Runtime del nodo | `containerd` | Evita depender del runtime predeterminado de una versión futura. |
| kubectl | `v1.37.0` recomendado | Mantiene la versión del cliente alineada con el servidor. |

El lock file se encuentra en
`terraform/environments/development/.terraform.lock.hcl`. Incluye los hashes publicados por el
registry para que el provider pueda instalarse tanto en `darwin_arm64` como en `linux_amd64`.

## Prerrequisitos

- macOS ARM64 o Linux AMD64.
- Terraform `1.16.7`.
- Docker Desktop o Docker Engine funcionando y accesible por el usuario.
- Minikube CLI `1.39.0` para inspección y recuperación manual.
- kubectl compatible con Kubernetes `v1.37.0`.
- Al menos 4 CPU, 6 GiB de memoria y 20 GiB de disco disponibles para Docker.
- Acceso a Internet durante la primera inicialización y creación para descargar el provider y las
  imágenes de Minikube/Kubernetes.

Comprobación recomendada:

```bash
terraform version
minikube version
kubectl version --client
docker info
```

## Crear el clúster

Desde la raíz del repositorio:

```bash
terraform fmt -check -recursive terraform
cd terraform/environments/development
terraform init -backend=false -input=false
terraform validate
terraform plan -input=false -out=taskflow-development.tfplan
terraform apply -input=false taskflow-development.tfplan
```

El plan se guarda solamente de forma local. Los archivos `*.tfplan`, estados, variables locales y
el directorio `.terraform/` están ignorados por Git.

El contexto anterior de kubectl se conserva. Los comandos de operación usan siempre el contexto
explícito para no actuar accidentalmente sobre otro clúster:

```bash
terraform output
kubectl --context taskflow-development cluster-info
kubectl --context taskflow-development get nodes -o wide
minikube status --profile taskflow-development
```

El nodo debe aparecer con estado `Ready` y versión `v1.37.0`.

## Comprobar idempotencia

Después de crear y verificar el clúster:

```bash
terraform plan -input=false -detailed-exitcode
```

El resultado esperado es `No changes` y código de salida `0`. El código `2` significa que Terraform
detectó cambios y debe revisarse antes de continuar.

## Destruir el clúster

La eliminación normal se realiza desde `terraform/environments/development`:

```bash
terraform destroy -input=false
terraform state list
minikube profile list
docker ps --all --filter name=taskflow-development
```

Después de confirmar el destroy:

- `terraform state list` no debe mostrar recursos.
- El perfil `taskflow-development` no debe aparecer en Minikube.
- Docker no debe conservar un contenedor con ese nombre.

Si una interrupción externa impide que Terraform finalice, inspeccionar primero el estado y utilizar
como recuperación manual:

```bash
minikube delete --profile taskflow-development
```

Este comando es solamente una recuperación operativa; no forma parte de la implementación
declarativa.

## Variables

| Variable | Tipo | Predeterminado | Validación relevante |
|---|---|---:|---|
| `cluster_name` | `string` | `taskflow-development` | Etiqueta DNS en minúsculas, de 3 a 63 caracteres. |
| `driver` | `string` | `docker` | Solamente `docker`; se excluyen drivers privilegiados o del host. |
| `kubernetes_version` | `string` | `v1.37.0` | Solamente la versión verificada. |
| `cpus` | `number` | `4` | Entero entre 2 y 8. |
| `memory` | `number` | `6` | GiB enteros entre 2 y 16. |
| `disk_size` | `number` | `20` | GiB enteros entre 10 y 50. |
| `nodes` | `number` | `1` | Entero entre 1 y 3. |

El módulo también limita el total solicitado a 8 CPU, 16 GiB de memoria y 60 GiB de disco entre
todos los nodos. Esto evita combinaciones válidas individualmente pero peligrosas para una máquina
local.

Para sobrescribir valores:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` no se versiona. El archivo de ejemplo no contiene secretos.

## Outputs

| Output | Contenido |
|---|---|
| `cluster_name` | Nombre del perfil Minikube. |
| `kubernetes_context` | Contexto que se debe pasar a kubectl. |
| `cluster_api_endpoint` | Endpoint no sensible del API server. |
| `verification_command` | Comando de solo lectura para comprobar los nodos. |

El provider no expone una ruta de kubeconfig. Minikube utiliza por defecto `~/.kube/config` o la ruta
indicada mediante `KUBECONFIG`. No se expone el contenido del kubeconfig, certificados ni claves.

## Addons base

Minikube habilita `default-storageclass` y `storage-provisioner` como componentes base incluso con
`install_addons = false`. El provider los devuelve durante la lectura del estado. Se declaran
explícitamente para evitar un plan perpetuo, pero no se habilitan Ingress, metrics-server, dashboard
ni componentes de TaskFlow.

## Integración continua

El job `Terraform format and validation` de `.github/workflows/ci.yml` ejecuta en Ubuntu AMD64:

```bash
terraform fmt -check -recursive terraform
terraform init -backend=false -input=false
terraform validate -no-color
```

El job de seguridad ejecuta además Checkov `3.3.29` específicamente sobre `terraform/`. Esta etapa
es estática: no crea un clúster en cada push y no utiliza secretos cloud. La configuración queda
preparada para agregar posteriormente una prueba efímera de infraestructura con `destroy` bajo
`always()`.

## Validación local realizada

Validación ejecutada el 30 de octubre de 2026 en Apple Silicon ARM64:

| Comprobación | Resultado real |
|---|---|
| `terraform fmt -check -recursive terraform` | Correcto, sin archivos fuera de formato. |
| `terraform init -backend=false -input=false` | Correcto; provider `0.8.0` instalado y lock file generado. |
| `terraform validate -no-color` | `Success! The configuration is valid.` |
| Plan inicial | `1 to add, 0 to change, 0 to destroy`. |
| `terraform apply` | `1 added`; 4 min 36 s con caché fría y 18 s en el ciclo final con imágenes locales. |
| `kubectl cluster-info` | API server y CoreDNS accesibles. |
| `kubectl get nodes -o wide` | Nodo `taskflow-development` `Ready`, Kubernetes `v1.37.0`, ARM64 y containerd `2.3.4`. |
| Segundo plan | `No changes`, código de salida `0`. |
| Checkov Terraform `3.3.29` | Código de salida `0`, sin hallazgos bloqueantes. |
| Checkov Dockerfile/Actions/YAML | 318 controles aprobados, 0 fallidos. |
| `terraform destroy` | `1 destroyed`; destrucción completada en 7-8 s. |
| Confirmación final | Estado vacío, 0 perfiles Minikube, 0 contenedores y 0 contextos en el kubeconfig temporal. |

La primera comprobación de idempotencia reveló drift en los dos addons base que Minikube activa
automáticamente. Se declararon de forma explícita y el plan repetido finalizó limpio.

## Limitaciones y riesgos

- El provider es comunitario, anterior a `1.0` y está autofirmado por su mantenedor, no por
  HashiCorp. Debe actualizarse solamente mediante una revisión deliberada del provider y del lock
  file.
- El provider guarda certificados y la clave cliente como atributos sensibles dentro del estado.
  Por ese motivo el estado local no puede versionarse, publicarse ni conservarse como artefacto.
- La ruta del kubeconfig no está disponible como atributo del provider.
- Docker Desktop debe estar iniciado y disponer de recursos suficientes. La prueba utilizó un
  engine con 10 CPU y 8 GB de memoria; el clúster reservó 4 CPU y 6 GiB.
- La creación inicial tarda varios minutos porque descarga la imagen base y componentes de
  Kubernetes.
- El binario kubectl local que existía inicialmente era `v1.34.1`, fuera del rango recomendado para
  un servidor `v1.37.0`; la validación se hizo con un binario temporal `v1.37.0` verificado por
  checksum.
- Minikube es un entorno de desarrollo y pruebas. El directorio `production` permanece reservado y
  no simula infraestructura productiva.
- La publicación multi-arquitectura, Ingress, HPA y PostgreSQL se implementan fuera de Terraform
  mediante GitHub Actions y manifiestos Kubernetes. Prometheus y Grafana pertenecen a una etapa
  posterior.

## Referencias

- [Provider comunitario de Minikube](https://registry.terraform.io/providers/scott-the-programmer/minikube/0.8.0/docs)
- [Recurso `minikube_cluster`](https://registry.terraform.io/providers/scott-the-programmer/minikube/0.8.0/docs/resources/cluster)
- [Minikube v1.39.0](https://github.com/kubernetes/minikube/releases/tag/v1.39.0)
- [Drivers de Minikube](https://minikube.sigs.k8s.io/docs/drivers/)
