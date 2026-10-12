# Entorno local con Docker

TaskFlow API se ejecuta localmente mediante Docker Compose. No es necesario instalar Python ni PostgreSQL en el host.

## Requisitos

- Docker Engine o Docker Desktop.
- Docker Compose v2.

## Configuración

Las variables predeterminadas permiten iniciar el proyecto directamente. Para personalizarlas, crea un archivo local `.env` a partir del ejemplo:

```bash
cp .env.example .env
```

El archivo `.env` no debe versionarse.

## Servicios

| Servicio | Función |
|---|---|
| `db` | Base PostgreSQL persistente de desarrollo. |
| `migrate` | Ejecuta `alembic upgrade head` antes de iniciar la API. |
| `api` | Ejecuta FastAPI con recarga automática en el puerto `8000`. |
| `db-test` | PostgreSQL temporal y aislado para pruebas. |
| `test` | Ejecuta migraciones, lint y pruebas dentro de Docker. |

Los servicios `db-test` y `test` pertenecen al perfil `test` y no se levantan durante el uso normal.

## Iniciar el entorno

```bash
docker compose up --build
```

La API quedará disponible en:

- API: <http://localhost:8000>
- Swagger UI: <http://localhost:8000/docs>
- Liveness: <http://localhost:8000/health/live>
- Readiness: <http://localhost:8000/health/ready>

Para iniciar los servicios en segundo plano:

```bash
docker compose up --build -d
```

## Consultar el estado y los logs

```bash
docker compose ps
docker compose logs -f api
```

## Acceder a PostgreSQL

```bash
docker compose exec db psql -U taskflow -d taskflow
```

PostgreSQL no publica su puerto hacia el host. La API accede a la base mediante el nombre DNS interno `db`.

## Ejecutar pruebas

```bash
docker compose --profile test run --build --rm test
```

El contenedor de pruebas utiliza `db-test`, ejecuta las migraciones y luego inicia Pytest. Sus datos se guardan en memoria temporal y se descartan al detener el servicio.

Para retirar el contenedor auxiliar de PostgreSQL después de las pruebas:

```bash
docker compose --profile test rm --stop --force db-test
```

## Detener el entorno

Detener los contenedores conservando la base de datos:

```bash
docker compose down
```

Eliminar también el volumen y todos los datos locales:

```bash
docker compose down -v
```

El último comando es destructivo y debe utilizarse únicamente cuando se quiera reiniciar la base de datos.
