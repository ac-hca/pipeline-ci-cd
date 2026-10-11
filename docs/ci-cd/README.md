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
