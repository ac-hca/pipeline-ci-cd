# Contrato de la API

Este documento define el contrato funcional inicial de TaskFlow API. Por el momento representa el diseño acordado; todavía no existe una implementación.

## Convenciones generales

- Formato de intercambio: JSON.
- Prefijo de la API: `/api/v1`.
- Fechas: ISO 8601 en UTC.
- Identificadores: UUID.
- Documentación interactiva prevista: `/docs`.
- Esquema OpenAPI previsto: `/openapi.json`.

## Recurso `Task`

| Campo | Tipo | Obligatorio al crear | Descripción |
|---|---|---:|---|
| `id` | UUID | No | Identificador generado por la aplicación. |
| `title` | string | Sí | Título de la tarea, entre 3 y 120 caracteres. |
| `description` | string o null | No | Descripción opcional de la tarea. |
| `status` | enum | No | `pending`, `in_progress` o `completed`. |
| `priority` | enum | No | `low`, `medium` o `high`. |
| `due_date` | datetime o null | No | Fecha límite opcional. |
| `created_at` | datetime | No | Fecha de creación generada por la aplicación. |
| `updated_at` | datetime | No | Fecha de la última modificación. |

### Reglas del recurso

- Una tarea nueva comienza con estado `pending` si no se indica otro valor permitido.
- La prioridad predeterminada es `medium`.
- El título no puede estar vacío y debe tener entre 3 y 120 caracteres.
- `created_at` y `updated_at` son campos administrados por la aplicación.
- Las actualizaciones parciales solo modifican los campos enviados.

## Endpoints

| Método | Ruta | Función | Respuesta exitosa |
|---|---|---|---:|
| `GET` | `/` | Obtener información general de la API. | `200` |
| `GET` | `/health/live` | Confirmar que el proceso está vivo. | `200` |
| `GET` | `/health/ready` | Confirmar que la aplicación está lista para recibir tráfico. | `200` |
| `POST` | `/api/v1/tasks` | Crear una tarea. | `201` |
| `GET` | `/api/v1/tasks` | Listar y filtrar tareas. | `200` |
| `GET` | `/api/v1/tasks/{id}` | Obtener una tarea por ID. | `200` |
| `PATCH` | `/api/v1/tasks/{id}` | Modificar parcialmente una tarea. | `200` |
| `DELETE` | `/api/v1/tasks/{id}` | Eliminar una tarea. | `204` |

## Detalle de operaciones

### Información general

`GET /`

Devuelve el nombre de la aplicación, su versión y el entorno en el que se está ejecutando.

Respuesta conceptual:

```json
{
  "name": "TaskFlow API",
  "version": "0.1.0",
  "environment": "development"
}
```

### Estado de vida

`GET /health/live`

Indica que el proceso de la API está en ejecución. No comprueba dependencias externas.

```json
{
  "status": "alive"
}
```

### Estado de disponibilidad

`GET /health/ready`

Comprueba que la aplicación y sus dependencias necesarias, como la base de datos, están disponibles. Si alguna dependencia crítica no responde, devolverá `503 Service Unavailable`.

```json
{
  "status": "ready"
}
```

### Crear una tarea

`POST /api/v1/tasks`

Solicitud conceptual:

```json
{
  "title": "Preparar despliegue",
  "description": "Validar la versión antes de desplegar",
  "priority": "high",
  "due_date": "2026-10-20T18:00:00Z"
}
```

Respuesta conceptual:

```json
{
  "id": "8e743b53-5582-45bc-aefd-54f989ed51d1",
  "title": "Preparar despliegue",
  "description": "Validar la versión antes de desplegar",
  "status": "pending",
  "priority": "high",
  "due_date": "2026-10-20T18:00:00Z",
  "created_at": "2026-10-11T15:00:00Z",
  "updated_at": "2026-10-11T15:00:00Z"
}
```

### Listar tareas

`GET /api/v1/tasks`

Filtros opcionales previstos:

| Parámetro | Tipo | Descripción |
|---|---|---|
| `status` | enum | Filtra por estado. |
| `priority` | enum | Filtra por prioridad. |
| `limit` | integer | Cantidad máxima de resultados. |
| `offset` | integer | Cantidad de resultados que se omiten. |

La respuesta será una colección JSON, incluso cuando no existan resultados.

### Consultar una tarea

`GET /api/v1/tasks/{id}`

Devuelve la tarea correspondiente al UUID solicitado. Si el recurso no existe, devuelve `404 Not Found`.

### Modificar una tarea

`PATCH /api/v1/tasks/{id}`

Acepta uno o más campos modificables: `title`, `description`, `status`, `priority` o `due_date`. No permite modificar `id`, `created_at` ni `updated_at` directamente.

Solicitud conceptual:

```json
{
  "status": "completed"
}
```

### Eliminar una tarea

`DELETE /api/v1/tasks/{id}`

Elimina la tarea y devuelve una respuesta vacía con estado `204 No Content`. Si el recurso no existe, devuelve `404 Not Found`.

## Códigos de respuesta

| Código | Significado |
|---:|---|
| `200` | Consulta o modificación realizada correctamente. |
| `201` | Recurso creado correctamente. |
| `204` | Recurso eliminado correctamente, sin cuerpo de respuesta. |
| `404` | Recurso inexistente. |
| `422` | Datos de entrada inválidos. |
| `500` | Error interno no esperado. |
| `503` | Aplicación temporalmente no disponible. |

## Formato conceptual de errores

Los errores controlados tendrán una estructura consistente:

```json
{
  "error": {
    "code": "task_not_found",
    "message": "The requested task does not exist"
  }
}
```

Los mensajes de error no deben revelar credenciales, consultas internas, trazas ni detalles sensibles de infraestructura.

## Documentación complementaria

Las subcarpetas de este directorio quedan reservadas para documentar arquitectura, Docker, CI/CD, Terraform, Kubernetes, monitoreo, FinOps, evidencias e informe final a medida que avance el proyecto.
