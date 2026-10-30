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
| Infraestructura | Checkov | Docker Compose, GitHub Actions y futuros archivos Terraform/Kubernetes | Configuraciones inseguras detectadas. |
| Imagen | Trivy | Exportación TAR de la imagen final `runtime`, sin acceso al socket de Docker | Vulnerabilidades `HIGH` o `CRITICAL` que tengan corrección disponible. |

Las versiones de las herramientas están fijadas para que los resultados sean reproducibles.
Todos los jobs utilizan permisos de solo lectura sobre el repositorio y no reciben credenciales
de despliegue.

DAST no se ejecuta todavía. Se incorporará cuando exista un entorno de pruebas desplegado en
Minikube. En CI se analizará una URL temporal del mismo job y, localmente, una URL expuesta por el
clúster; no dependerá de un entorno cloud permanente.

## Publicación de la imagen aprobada

Después de que todos los controles anteriores y el smoke test finalicen correctamente, los pushes
a `main` y los tags de versión publican la imagen runtime en GHCR. La estrategia de permisos,
eventos y etiquetas se documenta en [Registro de imágenes](../registry/README.md).
