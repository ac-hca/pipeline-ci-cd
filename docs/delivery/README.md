# Entrega continua de TaskFlow API

El workflow `Continuous Delivery` demuestra que una imagen aprobada por CI puede convertirse en un
despliegue funcional y seguro. El entorno es un Minikube temporal en el runner: se crea, valida y
destruye dentro de la misma ejecución. No existe un clúster cloud ni un entorno productivo
persistente.

## Entrega continua, no despliegue permanente

El resultado del proceso es una versión comprobada y lista para promoverse. Cuando termina:

- los reportes permanecen como artifact de GitHub Actions durante 14 días;
- la imagen inmutable permanece en GHCR;
- los recursos Kubernetes, volúmenes, perfil y contenedor Minikube son eliminados;
- ningún servicio queda publicado permanentemente.

Esta decisión evita costos y credenciales cloud. Un despliegue persistente requerirá una plataforma
posterior, políticas de promoción y una estrategia de rollback diferente.

## Disparadores

`.github/workflows/cd.yml` se ejecuta de dos formas:

1. Automáticamente, mediante `workflow_run`, cuando `Continuous Integration` termina correctamente
   para un evento `push` sobre `main`.
2. Manualmente, mediante `workflow_dispatch`, usando el SHA actual de `main`.

Los pull requests no ejecutan CD y un CI fallido no inicia la entrega. La concurrencia está
serializada con `cancel-in-progress: false` para no cancelar una ejecución mientras destruye su
clúster.

No se aceptan parámetros de imagen. El workflow deriva siempre una referencia inmutable:

```text
ghcr.io/ac-hca/pipeline-ci-cd:sha-<7 caracteres del commit validado>
```

Antes de desplegar verifica que el label OCI `org.opencontainers.image.revision` coincida con el
SHA que completó CI. Nunca utiliza `latest` ni la etiqueta móvil `main`.

## Flujo completo

```text
CI exitoso sobre main
  |
  `-- Imagen multi-arquitectura sha-* publicada en GHCR
        |
        `-- CD obtiene el mismo SHA y la misma imagen
              |-- Terraform crea Minikube
              |-- Se instalan NGINX Ingress y Metrics Server
              |-- La imagen aprobada se carga en containerd
              |-- Se generan secretos efímeros
              |-- Kustomize despliega PostgreSQL, migración y API
              |-- Se esperan PostgreSQL, Job y rollout
              |-- Se comprueban idempotencia, métricas, HPA y PDB
              |-- Smoke tests validan Ingress, API y persistencia
              |-- OWASP ZAP analiza OpenAPI
              |-- Se recopilan evidencias
              `-- Terraform destruye Minikube siempre
```

## Versiones fijadas

| Componente | Versión |
|---|---:|
| Terraform | `1.16.7` |
| Minikube | `1.39.0` |
| Kubernetes y kubectl | `v1.37.0` |
| Helm | `4.3.1` |
| F5 NGINX Ingress Controller | `5.7.0` |
| Metrics Server | `0.9.0` |
| OWASP ZAP | `2.17.0` |
| ShellCheck | `0.11.0` |

El binario Minikube de Linux AMD64 se descarga desde su release oficial y se valida contra el
SHA-256 versionado en el workflow. La imagen ZAP se fija por versión, deshabilita actualizaciones de
add-ons durante el escaneo y registra su digest resuelto en las evidencias de cada ejecución.

El asset Linux AMD64 de Minikube `1.39.0` está fijado al digest
`b738496da01be06bbaf80c688f57ce25acd3849fbb518155f3a88e03ef555aa4`, comprobado contra el
archivo `.sha256` publicado por el release oficial.

## Permisos y autenticación

El workflow declara solamente:

```yaml
permissions:
  contents: read
  packages: read
```

El `GITHUB_TOKEN` temporal se utiliza únicamente para descargar la imagen privada de GHCR. No se
configuran OIDC, credenciales cloud ni Personal Access Tokens.

El kubeconfig se crea en `RUNNER_TEMP` y no se sube como artifact. El estado de Terraform también
permanece local al runner y queda excluido de las evidencias porque contiene material sensible del
clúster.

## Infraestructura controlada

Terraform ejecuta:

```bash
terraform init -input=false
terraform validate
terraform plan -out=<plan-temporal>
terraform apply <plan-temporal>
```

El plan binario se guarda en `RUNNER_TEMP`. Solo su representación de texto, donde Terraform
mantiene redacted los atributos sensibles, se conserva como evidencia.

El clúster usa el mismo módulo, driver Docker, Kubernetes y presupuesto de recursos verificados
localmente. Terraform no administra objetos Kubernetes.

## Despliegue y migraciones

La imagen descargada desde GHCR se retaggea localmente como `taskflow-api:k8s-dev` y se carga con:

```bash
minikube image load taskflow-api:k8s-dev --profile taskflow-development
```

Esto evita guardar un token de GHCR dentro del clúster temporal. Después se genera una contraseña
aleatoria mediante `openssl rand` y se escribe en el archivo ignorado
`kubernetes/overlays/development/secrets.env`.

Kustomize aplica el overlay development. El orden efectivo queda protegido por los recursos ya
implementados:

1. PostgreSQL debe superar su readiness.
2. El init container del Job espera una conexión real.
3. El Job ejecuta `alembic upgrade head`.
4. El init container de la API espera que Alembic alcance el head.
5. El Deployment completa su rollout y readiness.

Una segunda aplicación seguida de `kubectl diff` comprueba idempotencia.

## Pruebas de humo

`scripts/cd/smoke-test.sh` accede mediante NGINX y el host `taskflow.local`. Valida:

- `GET /health/live`;
- `GET /health/ready`;
- `GET /docs`;
- `POST /api/v1/tasks`;
- `GET /api/v1/tasks/{id}`;
- presencia de la tarea creada en `GET /api/v1/tasks`.

La creación y posterior lectura prueban Ingress, Service, API y PostgreSQL, no solamente que el
proceso responda HTTP.

## DAST con OWASP ZAP

`scripts/cd/run-zap.sh` ejecuta el API Scan oficial contra:

```text
/openapi.json
```

Es un escaneo activo autorizado exclusivamente sobre el Minikube temporal. No debe apuntarse a un
entorno ajeno o productivo sin autorización explícita.

La política `security/zap/rules.tsv` funciona así:

- inyecciones SQL, XSS, path traversal, ejecución de comandos, XXE y divulgación de errores son
  `FAIL` y bloquean la entrega;
- headers defensivos faltantes son `WARN` y quedan en el reporte;
- reglas no incluidas se conservan como `INFO`.

ZAP produce reportes HTML, JSON y Markdown. Su API Scan devuelve error operacional si no puede
importar OpenAPI o alcanzar la aplicación; ese caso también falla el workflow.

En Ubuntu GitHub Actions se usa la red host del contenedor. Docker Desktop en macOS necesita el
modo bridge:

```bash
kubectl --context taskflow-development -n taskflow-development \
  port-forward --address 0.0.0.0 service/taskflow-api 8000:80

ZAP_NETWORK_MODE=bridge \
ZAP_TARGET=http://host.docker.internal:8000/openapi.json \
EVIDENCE_DIR=delivery-evidence \
scripts/cd/run-zap.sh
```

El port-forward enlazado a `0.0.0.0` debe mantenerse solamente durante la prueba y cerrarse al
terminar. `delivery-evidence/` está ignorado por Git.

## Evidencias

El artifact `taskflow-delivery-<run-id>` contiene:

- SHA, referencia y digest de la imagen;
- plan textual y outputs no sensibles de Terraform;
- versiones de herramientas;
- cluster-info, nodos y namespaces;
- Pods, Services, Ingress, HPA, PDB, PVC y eventos;
- descripción y logs de API, PostgreSQL y migración;
- métricas de Pods;
- respuestas y resumen de smoke tests;
- reportes HTML, JSON y Markdown de ZAP;
- resultado de `terraform destroy` y confirmación de limpieza.

No se recopilan Secrets, kubeconfig, estado Terraform, plan binario ni credenciales. El script de
evidencias puede fallar al consultar un recurso ausente sin ocultar el problema principal; cada
archivo indica si su comando de diagnóstico falló.

## Fallos, cleanup y rollback

Si falla Terraform, Kubernetes, smoke o DAST:

1. el job queda fallido;
2. `if: always()` recopila diagnósticos antes de eliminar recursos;
3. se eliminan recursos y releases Helm cuando el API server está disponible;
4. `terraform destroy` se ejecuta siempre;
5. se comprueba que el estado, perfil y contenedor estén vacíos;
6. las evidencias se suben incluso en una ejecución fallida.

En un clúster recién creado no existe una revisión anterior útil para `kubectl rollout undo`.
Destruir el entorno inválido es el rollback correcto para esta arquitectura efímera. Una futura
plataforma persistente deberá promover imágenes SHA y revertir declarativamente a la referencia
anterior.

## Ejecutar desde GitHub

Flujo automático:

```text
push a main -> Continuous Integration -> publicación sha-* -> Continuous Delivery
```

Para repetir manualmente una entrega ya publicada:

1. Abrir **Actions**.
2. Elegir **Continuous Delivery**.
3. Seleccionar **Run workflow** sobre `main`.

La ejecución manual deriva la imagen SHA del commit actual. Fallará de manera segura si esa imagen
todavía no existe en GHCR.

## Validación local realizada

Prueba ejecutada el 1 de noviembre de 2026 en Apple Silicon ARM64:

| Comprobación | Resultado real |
|---|---|
| Terraform | Plan `1 to add`; Minikube creado y luego destruido. |
| Kubernetes | Nodo ARM64 `Ready`, versión `v1.37.0`. |
| Plataforma | NGINX `5.7.0` y Metrics Server `0.9.0` disponibles. |
| Imagen | Runtime ARM64 construido localmente y cargado en containerd. |
| Migraciones | Job Alembic completado antes del rollout. |
| API | Deployment disponible y probes correctas. |
| Idempotencia | Segunda aplicación y `kubectl diff` correctos. |
| Smoke | 6 operaciones validadas; tarea creada y recuperada por Ingress. |
| ZAP | 11 URLs importadas; 0 FAIL, 1 WARN, 2 INFO y 117 PASS. |
| ZAP resuelto | `ghcr.io/zaproxy/zaproxy@sha256:030d3df57735dacbb83464854758e674dd9ad01d79d12a129a8e58b1fd384238`. |
| HPA durante DAST | Escaló la API a 2 réplicas; métrica `cpu: 3%/70%`. |
| Evidencias | 30 archivos generados; sin secretos ni URLs de conexión. |
| Cleanup | Estado Terraform vacío, 0 perfiles y 0 contenedores Minikube. |

La prueba local construyó la imagen porque el commit de esta etapa todavía no había sido publicado.
La descarga desde GHCR y el encadenamiento real `workflow_run` solo pueden verificarse después del
push y de una ejecución exitosa en GitHub Actions.

## Limitaciones

- El workflow consume minutos de runner y descarga imágenes grandes, especialmente ZAP.
- Un clúster de un nodo no demuestra alta disponibilidad física.
- El artifact expira a los 14 días; las evidencias finales seleccionadas deberán conservarse en el
  informe del proyecto.
- Una cancelación forzada del runner puede impedir los pasos `always()`; la concurrencia no cancela
  ejecuciones activas y Terraform configura `delete_on_failure`, pero una ejecución interrumpida
  debe revisarse manualmente.
- El overlay de producción sigue siendo solo renderizable; CD despliega exclusivamente development.

## Referencias

- [OWASP ZAP API Scan](https://www.zaproxy.org/docs/docker/api-scan/)
- [Eventos workflow_run de GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Terraform para Minikube](../terraform/README.md)
- [Kubernetes para TaskFlow](../kubernetes/README.md)
