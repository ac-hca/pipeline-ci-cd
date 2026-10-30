# Terraform: alcance y handoff

Este documento prepara el punto 6 del proyecto. Su finalidad es que otro agente pueda implementar
Terraform respetando la decisión de plataforma registrada en
[Decisión de plataforma](../architecture/README.md).

## Objetivo

Crear un clúster Minikube local, parametrizado y reproducible mediante Terraform. La misma
configuración deberá poder validarse en la computadora de desarrollo y, posteriormente, en un
runner temporal de GitHub Actions.

Terraform administrará solamente la infraestructura base del clúster. Los Deployments, Services,
Ingress, HPA y demás objetos de la aplicación se implementarán como manifiestos durante la etapa
de Kubernetes.

## Alcance de la implementación

La siguiente etapa debe incluir:

- Provider de Minikube fijado a una versión compatible.
- Módulo reutilizable para crear y eliminar el clúster.
- Entorno `development` con valores apropiados para la máquina local.
- Variables validadas para nombre, driver, versión de Kubernetes, CPU, memoria, disco y nodos.
- Outputs que permitan identificar el nombre del clúster, el contexto y el kubeconfig.
- Archivo de ejemplo para valores configurables, sin secretos.
- Documentación de los comandos `init`, `fmt`, `validate`, `plan`, `apply` y `destroy`.
- Validaciones de Terraform y Checkov dentro de CI.
- Destrucción garantizada en pruebas automatizadas, incluso cuando falle un paso posterior.

## Estructura esperada

```text
terraform/
|-- modules/
|   `-- minikube-cluster/
|       |-- main.tf
|       |-- variables.tf
|       |-- outputs.tf
|       `-- versions.tf
`-- environments/
    `-- development/
        |-- main.tf
        |-- variables.tf
        |-- outputs.tf
        |-- versions.tf
        `-- terraform.tfvars.example
```

El directorio `terraform/environments/production/` permanece reservado. No debe implementarse un
entorno cloud ni simular producción durante este punto.

## Valores iniciales

| Variable conceptual | Valor predeterminado |
|---|---|
| Nombre del clúster | `taskflow-development` |
| Driver | `docker` |
| Nodos | `1` |
| CPU | `4` |
| Memoria | `6 GB` |
| Disco | `20 GB` |
| Kubernetes | Versión estable fijada explícitamente |

La versión exacta de Kubernetes y la versión del provider deben resolverse al implementar y quedar
registradas en el código y en `.terraform.lock.hcl`.

## Decisiones técnicas

- Usar preferentemente el recurso `minikube_cluster` del provider comunitario de Minikube.
- No utilizar `local-exec` para crear el clúster mientras el provider pueda administrar su ciclo
  de vida de forma declarativa.
- Mantener el estado local para esta actividad; no crear S3, Terraform Cloud ni otro backend pago.
- No administrar los manifiestos de TaskFlow con Terraform para evitar duplicar responsabilidades.
- No introducir AWS, EKS, ECR, GCP, Azure ni credenciales cloud.
- Mantener GHCR como registry acordado en el punto anterior.

## Prerrequisitos

La implementación debe comprobar y documentar:

- Terraform instalado.
- Minikube instalado.
- Docker Desktop funcionando.
- `kubectl` disponible, ya sea localmente o mediante Minikube.
- Capacidad suficiente en Docker Desktop para asignar los recursos definidos.

## Criterios de aceptación

El punto se considerará completo cuando se demuestre lo siguiente:

1. `terraform fmt -check -recursive` finaliza correctamente.
2. `terraform init` instala versiones fijadas de los providers.
3. `terraform validate` y Checkov no encuentran errores bloqueantes.
4. `terraform plan` describe la creación del clúster sin cambios inesperados.
5. `terraform apply` crea `taskflow-development`.
6. `kubectl cluster-info` responde y el nodo aparece como `Ready`.
7. Un segundo `terraform apply` no propone cambios, demostrando idempotencia.
8. `terraform destroy` elimina el clúster.
9. No se versionan estados, planes, kubeconfigs ni secretos.

## Integración continua prevista

El pipeline deberá separar dos niveles:

- En cada pull request: formato, inicialización sin backend, validación y análisis estático.
- En una prueba de infraestructura controlada: crear Minikube, verificar el nodo y ejecutar
  `terraform destroy` con una condición equivalente a `always()`.

El despliegue de TaskFlow, DAST, HPA y monitoreo se añadirá después de que esta base sea estable.

## Riesgos que el siguiente agente debe considerar

- El provider de Minikube no es mantenido por HashiCorp; debe fijarse su versión y verificarse su
  comportamiento tanto en macOS ARM64 como en Ubuntu AMD64.
- El driver Docker depende de los recursos asignados a Docker Desktop.
- La autenticación de un clúster local contra GHCR privado pertenece a la etapa de Kubernetes.
- La imagen multi-arquitectura también pertenece a una etapa posterior y no debe mezclarse con
  el commit inicial de Terraform.
- Si el provider no expone alguna opción de Minikube, se debe documentar la limitación antes de
  introducir comandos imperativos como solución alternativa.

## Fuera de alcance

- Recursos AWS o de cualquier otro proveedor cloud.
- K3s en un VPS.
- Manifiestos Kubernetes de la aplicación.
- Instalación de Prometheus y Grafana.
- Ejecución de DAST.
- Evidencias finales y video.
