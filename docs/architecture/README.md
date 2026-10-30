# Decisión de plataforma

Este documento registra la decisión tomada para el punto 5 del proyecto y establece el contexto
que debe utilizarse en las etapas de Terraform, Kubernetes, monitoreo y FinOps.

## Decisión

El entorno de pruebas oficial será un clúster local de **Minikube**. No se utilizarán AWS, EKS,
ECR ni otros servicios cloud obligatorios.

La solución se diseñará para que pueda ejecutarse de dos maneras:

1. Localmente, en la computadora de desarrollo, para demostraciones, capturas y grabación del
   video final.
2. Temporalmente, en un runner de GitHub Actions, para validar de forma automática la creación
   del clúster, el despliegue y las pruebas.

Un VPS con K3s queda como extensión opcional únicamente si la evaluación exige posteriormente
una URL pública o un entorno remoto persistente. No forma parte del alcance actual.

## Motivos

- La consigna requiere Terraform y Kubernetes, pero no exige un proveedor cloud.
- Minikube permite reproducir la solución sin credenciales ni costos de infraestructura.
- El clúster puede eliminarse y reconstruirse, lo que demuestra infraestructura reproducible.
- El evaluador podrá ejecutar el proyecto localmente siguiendo la documentación.
- Los logs de GitHub Actions, las capturas y el video conservarán evidencia aunque el clúster
  local esté apagado.
- Evita mantener un clúster administrado que genere costos mientras no se utiliza.

## Arquitectura objetivo

```text
GitHub
  |-- GitHub Actions: build, test, seguridad y automatización
  |-- GHCR privado: imagen runtime versionada por SHA
  |
  `-- Terraform
        `-- Minikube: clúster Kubernetes local y efímero
              |-- TaskFlow API
              |-- PostgreSQL
              |-- Ingress y Services
              |-- HPA y metrics-server
              `-- Prometheus y Grafana
```

Terraform será responsable del ciclo de vida del clúster. Los recursos de la aplicación se
mantendrán como manifiestos Kubernetes, porque la consigna los solicita explícitamente y deben
poder aplicarse también a un futuro K3s o clúster administrado.

## Correspondencia con la actividad

| Requisito | Implementación acordada |
|---|---|
| Infraestructura | Terraform crea y elimina Minikube. |
| Redes | Red interna y CNI del clúster local. |
| Instancia | Nodo local de Minikube ejecutado como contenedor o máquina virtual. |
| Clúster Kubernetes | Minikube de un nodo. |
| Registry | GHCR privado, ya implementado. |
| Despliegue | Manifiestos versionados en `kubernetes/`. |
| Ingress | Controlador instalado explícitamente para el entorno local. |
| Autoescalado | HPA basado en métricas de CPU. |
| Monitoreo | Prometheus y Grafana con límites de recursos. |
| FinOps | Límites, HPA, clúster efímero, pausa y eliminación. |
| Evidencias | Artefactos de CI, logs, capturas y video local. |

## Presupuesto local de recursos

La máquina de desarrollo dispone de 24 GB de RAM y 10 núcleos. El clúster debe respetar estos
valores iniciales para no degradar innecesariamente el equipo:

| Recurso | Valor inicial |
|---|---:|
| Nodos | 1 |
| CPU | 4 |
| Memoria | 6 GB |
| Disco | 20 GB |

Los componentes desplegados deben declarar `requests` y `limits`. Prometheus conservará solamente
las métricas necesarias para la demostración y no se configurará alta disponibilidad.

## Límites aceptados

- Minikube es un entorno de desarrollo y pruebas, no de producción.
- El HPA podrá escalar Pods, pero un clúster de un nodo no demostrará escalado de máquinas.
- La red local no reproduce balanceadores ni zonas de disponibilidad de un proveedor cloud.
- El provider de Terraform para Minikube es comunitario y deberá fijarse a una versión concreta.
- En macOS con el driver Docker no se debe depender del addon de Ingress de Minikube. El
  controlador se instalará explícitamente durante la etapa de Kubernetes.
- La imagen publicada actualmente por GitHub Actions se construye en `linux/amd64`, mientras que
  la máquina local usa Apple Silicon. Antes del despliegue desde GHCR se deberá publicar una
  imagen multi-arquitectura o cargar en Minikube una imagen construida localmente para `arm64`.

Estas diferencias deben explicarse en el informe final; no invalidan la demostración académica.

## Seguridad y costos

- No se incorporarán credenciales cloud.
- Los tokens de GHCR no se guardarán en el repositorio ni dentro de manifiestos versionados.
- El estado de Terraform, los planes y los kubeconfigs locales permanecerán ignorados por Git.
- `terraform destroy` deberá eliminar el clúster cuando termine una prueba automatizada.
- Localmente se utilizará `minikube stop` para liberar CPU y memoria, o `minikube delete` para
  eliminar completamente el entorno.

## Referencias

- [Inicio y requisitos de Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Drivers disponibles](https://minikube.sigs.k8s.io/docs/drivers/)
- [Provider comunitario de Minikube](https://registry.terraform.io/providers/scott-the-programmer/minikube/latest/docs)
- [Provider oficial de Kubernetes con Minikube](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/getting-started.html)
