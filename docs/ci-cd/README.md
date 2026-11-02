# Estrategia de commits

Usaré una estructura basada en Conventional Commits, con cambios pequeños, descriptivos y verificables.

## Formato

```text
tipo(alcance): descripción breve
```

Ejemplos:

```text
docs(api): define initial REST contract
feat(tasks): implement task creation endpoint
test(tasks): cover task validation rules
build(docker): add optimized multistage image
ci(actions): automate tests and image publishing
infra(terraform): define reusable network module
deploy(k8s): configure application service and ingress
security(ci): integrate SAST and DAST checks
```

## Tipos principales

- `feat`: funcionalidad de la API.
- `fix`: corrección de errores.
- `test`: pruebas.
- `docs`: documentación.
- `build`: dependencias, empaquetado o Docker.
- `ci`: GitHub Actions.
- `infra`: Terraform y recursos cloud.
- `deploy`: Kubernetes y despliegues.
- `security`: controles y análisis de seguridad.
- `observability`: Prometheus, Grafana y métricas.
- `finops`: optimizaciones de costos.
- `chore`: organización o mantenimiento sin funcionalidad nueva.

## Cada commit seguirá estas reglas

- Un solo propósito lógico.
- Descripción en inglés, breve y en presente.
- No mezclar documentación, infraestructura y aplicación sin necesidad.
- Incluir las pruebas junto con la funcionalidad cuando formen una unidad inseparable.
- Ejecutar las validaciones correspondientes antes del commit.
- Nunca incluir secretos, credenciales, estados de Terraform ni artefactos generados.
- No crear commits de código incompleto o que rompan deliberadamente el proyecto.

## Seguridad temprana en CI

El workflow de integración continua ejecuta controles de seguridad antes de habilitar la
prueba de la imagen runtime:

| Control | Herramienta | Alcance | Criterio de bloqueo |
|---|---|---|---|
| SAST | Bandit | Código Python de `app/` | Hallazgos de severidad y confianza media o superior. |
| Dependencias | pip-audit | Dependencias declaradas en `requirements.txt` | Vulnerabilidades conocidas sin una exclusión explícita. |
| Secretos | Gitleaks | Historial Git completo | Cualquier credencial o secreto detectado. |
| Dockerfile | Hadolint | `docker/Dockerfile` | Incumplimientos de buenas prácticas del linter. |
| Infraestructura | Checkov | Docker Compose, GitHub Actions, Terraform y manifiestos Kubernetes renderizados | Configuraciones inseguras detectadas. |
| Imagen | Trivy | Exportación TAR de la imagen final `runtime`, sin acceso al socket de Docker | Vulnerabilidades `HIGH` o `CRITICAL` que tengan corrección disponible. |

Las versiones de las herramientas están fijadas para que los resultados sean reproducibles.
Todos los jobs utilizan permisos de solo lectura sobre el repositorio y no reciben credenciales
de despliegue.

DAST se ejecuta en el workflow separado `Continuous Delivery`, después de crear un Minikube
temporal y desplegar la imagen inmutable aprobada. OWASP ZAP `2.17.0` analiza el contrato OpenAPI;
las reglas bloqueantes y los reportes se documentan en
[Entrega continua de TaskFlow](../delivery/README.md).

## Validación de Terraform

El workflow ejecuta un job independiente para comprobar el formato de todos los archivos Terraform,
inicializar el entorno `development` sin backend remoto y validar su configuración. La versión de
Terraform está fijada y el provider Minikube se resuelve mediante el lock file versionado.

Checkov analiza `terraform/` en un paso explícito. Esta validación no crea infraestructura, no
requiere credenciales cloud y no administra GHCR. Después de un CI exitoso sobre `main`, el
workflow de entrega ejecuta el ciclo real `plan`, `apply`, verificación y `destroy` en un runner
temporal.

## Validación de Kubernetes

El job `Kubernetes manifests` utiliza kubectl `v1.37.0` y entradas de ejemplo no sensibles para:

- rechazar archivos de secretos runtime que hayan sido versionados;
- renderizar los overlays `development` y `production` con Kustomize;
- validar 30 recursos con Kubeconform `0.8.0` en modo estricto;
- ejecutar Checkov `3.3.29` sobre el resultado completo, no sobre parches aislados.

Los manifiestos renderizados se escriben en el directorio temporal del runner y no se conservan
como artefactos. El overlay de producción se valida, pero no se despliega. El ciclo real de
Minikube, PostgreSQL, migraciones, API, Ingress, métricas y cleanup fue probado localmente y se
documenta en [Kubernetes para TaskFlow API](../kubernetes/README.md).

El workflow de entrega despliega únicamente development y ejecuta `terraform destroy` bajo
`if: always()`. Producción continúa siendo un overlay renderizable y no se aplica.

## Publicación de la imagen aprobada

Después de que todos los controles anteriores y el smoke test finalicen correctamente, los pushes
a `main` y los tags de versión publican la imagen runtime en GHCR. Buildx y QEMU generan un único
manifest list para `linux/amd64` y `linux/arm64`; se mantienen las etiquetas `sha-*`, `main` y
`vX.Y.Z` según el evento. La estrategia de permisos, eventos y etiquetas se documenta en
[Registro de imágenes](../registry/README.md).

## Entrega de la imagen aprobada

`Continuous Delivery` se activa solo después de que el workflow completo de CI finaliza con éxito
para un push a `main`. El SHA del evento determina el checkout y la etiqueta `sha-*`; el label OCI
de la imagen debe coincidir antes de crear infraestructura.

El workflow usa permisos `contents: read` y `packages: read`, genera secretos de prueba temporales,
ejecuta migraciones, rollout, smoke tests y OWASP ZAP, y conserva evidencias durante 14 días. Los
detalles operativos y el comportamiento de cleanup se encuentran en
[Entrega continua de TaskFlow](../delivery/README.md).
