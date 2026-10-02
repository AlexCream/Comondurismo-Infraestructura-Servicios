# Infraestructura de desarrollo

PostgreSQL, Redis y Mailpit para desarrollar el servicio de identidad. **No forma parte del
servicio**: puedes mover esta carpeta fuera del repositorio sin cambiar nada del servicio.

```bash
cp .env.example .env     # define POSTGRES_PASSWORD y REDIS_PASSWORD
docker compose up -d
docker compose ps        # espera a que postgres y redis estén "healthy"
```

Crea la red `comondurismo-network`, a la que se conectan los demás contenedores
(el del servicio, y más adelante los de otros servicios) para encontrarse por nombre.

## Cómo encuentra el servicio estas piezas

Solo por variables de entorno en el `.env` **del servicio**. Según dónde corra el servicio:

| El servicio corre… | `DATABASE_URL` | `REDIS_ADDR` | `SMTP_HOST` / `SMTP_PORT` |
|---|---|---|---|
| En un contenedor, en la red `comondurismo-network` | `postgres://USUARIO:CLAVE@postgres:5432/BASE?sslmode=disable` | `redis:6379` | `mailpit` / `1025` |
| En un contenedor, sin esa red (usa tu máquina) | `…@host.docker.internal:5432/…` | `host.docker.internal:6379` | `host.docker.internal` / `1025` |
| Directo en tu máquina (`go run ./cmd/api`) | `…@127.0.0.1:5432/…` | `127.0.0.1:6379` | `127.0.0.1` / `1025` |

`USUARIO`, `CLAVE` y `BASE` son `POSTGRES_USER`, `POSTGRES_PASSWORD` y `POSTGRES_DB` de este
`.env`; la contraseña de Redis (`REDIS_PASSWORD`) debe ser la misma en ambos archivos.
Si la contraseña tiene caracteres especiales (`@ : / ? #`), codifícalos en la URL
(por ejemplo `@` → `%40`) o usa una contraseña alfanumérica.

## Después de levantarla

1. La base está **vacía**: aplica las migraciones desde el servicio
   (`docker run --rm --env-file .env <imagen> /migrate up`, o `AUTO_MIGRATE=true`).
2. Los correos del servicio se ven en <http://localhost:8025>.

## Datos y reinicio

Los datos viven en los volúmenes `postgres_data` y `redis_data`. Para empezar de cero
(borra todo): `docker compose down -v`. Si cambias el nombre de esta carpeta o la mueves,
Docker Compose crea volúmenes nuevos y la base arranca vacía.

## Nota sobre PostGIS

El servicio de identidad no usa PostGIS. La imagen `postgis/postgis` se conserva porque el
servicio de contenido (lugares, mapa) sí lo necesitará; si esta infraestructura es solo para
identidad, puedes usar `postgres:16`.
