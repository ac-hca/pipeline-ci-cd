# Registro de imágenes

La imagen de ejecución de TaskFlow API se publica en GitHub Container Registry (GHCR):

```text
ghcr.io/ac-hca/pipeline-ci-cd
```

La publicación forma parte del workflow de integración continua. No se publica ninguna imagen
desde un pull request ni antes de que finalicen correctamente las migraciones, pruebas, controles
de calidad, análisis de seguridad y smoke test de la imagen runtime.

## Estrategia de etiquetas

| Evento | Etiquetas publicadas | Finalidad |
|---|---|---|
| Push a `main` | `sha-<7 caracteres>` y `main` | Identificar el commit exacto y mantener una referencia al último build aprobado de la rama principal. |
| Push de un tag `vX.Y.Z` | `sha-<7 caracteres>` y `vX.Y.Z` | Publicar una versión identificable para despliegues y rollbacks. |
| Pull request | Ninguna | Validar el cambio sin escribir en el registry. |

Ejemplo para el commit `ef76408` y la versión `v0.1.0`:

```text
ghcr.io/ac-hca/pipeline-ci-cd:sha-ef76408
ghcr.io/ac-hca/pipeline-ci-cd:main
ghcr.io/ac-hca/pipeline-ci-cd:v0.1.0
```

No se publica `latest`. Esta etiqueta no permite conocer de forma directa qué commit o versión
está desplegada. Para Kubernetes se utilizará preferentemente una etiqueta `sha-*` o `vX.Y.Z`.

`main` es una etiqueta móvil: cambia con cada push aprobado. Una etiqueta `sha-*` identifica el
commit que originó el build. Los tags de Git `vX.Y.Z` no deben moverse ni reutilizarse para otra
versión.

## Visibilidad y vinculación

El paquete se mantendrá privado, igual que el repositorio. La primera publicación de GHCR tiene
visibilidad privada de manera predeterminada. Además, el label OCI
`org.opencontainers.image.source` vincula la imagen con este repositorio para que pueda heredar su
acceso.

La visibilidad se revisará después de la primera publicación en **Packages > Package settings**.
No debe cambiarse a pública durante esta etapa del proyecto.

## Autenticación del workflow

GitHub Actions inicia sesión en GHCR con el `GITHUB_TOKEN` temporal creado automáticamente para
cada ejecución. El job de publicación declara solamente estos permisos:

```yaml
permissions:
  contents: read
  packages: write
```

No se necesita guardar un Personal Access Token, usuario o contraseña como secreto del
repositorio. El token no se entrega a los jobs de validación y la publicación no se ejecuta en
pull requests.

La imagen incorpora etiquetas OCI con la URL del repositorio, el SHA completo y la referencia de
Git utilizada durante el build. Estas etiquetas permiten relacionar el artefacto con su código
fuente.

## Publicar desde `main`

Después de subir un commit a `main`, el workflow publica automáticamente:

```text
ghcr.io/ac-hca/pipeline-ci-cd:sha-<sha-corto>
ghcr.io/ac-hca/pipeline-ci-cd:main
```

No se debe ejecutar un `docker push` manual para este flujo.

## Publicar una versión

Las versiones siguen Semantic Versioning con el formato `vMAJOR.MINOR.PATCH`. Por ejemplo:

```bash
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

El tag activa todas las validaciones del workflow. La imagen `v0.1.0` se publica únicamente si
todas finalizan correctamente.

## Descargar una imagen privada

Para descargar manualmente una imagen privada se necesita un token de GitHub con permiso de
lectura de paquetes. El token debe permanecer fuera del repositorio:

```bash
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username ac-hca --password-stdin
docker pull ghcr.io/ac-hca/pipeline-ci-cd:sha-ef76408
```

Cuando la imagen privada se utilice en Minikube, la autenticación se configurará mediante un
Secret creado en tiempo de ejecución. Como alternativa para el desarrollo, se podrá cargar una
imagen construida localmente en el clúster. El token nunca se escribirá directamente en un
manifiesto ni se guardará en el repositorio.

## Verificación

Después de que el workflow termine:

1. Abrir el repositorio en GitHub y consultar la sección **Packages**.
2. Confirmar que existen la etiqueta SHA y la etiqueta correspondiente al evento.
3. Descargar la etiqueta SHA.
4. Consultar la revisión OCI incorporada en la imagen:

```bash
docker image inspect ghcr.io/ac-hca/pipeline-ci-cd:sha-ef76408 \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
```

El resultado debe ser el SHA completo del commit usado por GitHub Actions.

## Uso posterior en despliegues

Los manifiestos de Kubernetes no dependerán de `main`. Un despliegue utilizará una referencia
inmutable y verificable, por ejemplo:

```yaml
image: ghcr.io/ac-hca/pipeline-ci-cd:sha-ef76408
```

Esto permite conocer exactamente qué código está ejecutándose y volver a una imagen anterior sin
reconstruirla.

La imagen publicada actualmente se construye en un runner `linux/amd64`. Antes de utilizarla en
la máquina Apple Silicon del proyecto se deberá habilitar una publicación multi-arquitectura o
usar una imagen local `arm64`. Esta adaptación se realizará durante la etapa de Kubernetes y no
modifica la estrategia de etiquetas.
