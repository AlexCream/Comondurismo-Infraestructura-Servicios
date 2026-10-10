# Infraestructura de desarrollo

PostgreSQL, Redis, Mailpit, un almacenamiento de objetos compatible con S3 y el gateway para
desarrollar los servicios de identidad y de contenido. **No forma parte de los servicios**:
puedes mover esta carpeta fuera de sus repositorios sin cambiar nada de ellos.

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

## Contenido: base de datos y almacenamiento de objetos

- **Base de contenido.** Cada servicio tiene su propia base, sin compartir tablas. La primera
  vez que arranca PostgreSQL con un volumen vacío, `postgres/initdb/10-content-database.sh` crea
  `comondurismo_content` (nombre en `POSTGRES_CONTENT_DB`). Si el volumen ya existía, créala a
  mano una vez:

  ```bash
  docker exec comondurismo-postgres psql -U <POSTGRES_USER> -d postgres -c "CREATE DATABASE comondurismo_content"
  ```

  y aplica las migraciones desde el servicio de contenido (`/migrate up`). Las extensiones
  (`postgis`, `pg_trgm`, `unaccent`) las crea su primera migración.
- **Almacenamiento de objetos** (`storage`, RustFS): guarda las imágenes y los videos del
  servicio de contenido. API S3 en `127.0.0.1:9000` (`storage:9000` dentro de la red de Docker) y
  consola web en <http://localhost:9001>. Las llaves son `S3_ACCESS_KEY` y `S3_SECRET_KEY`
  (el servicio de contenido las usa como `OBJECT_STORE_ACCESS_KEY` y `OBJECT_STORE_SECRET_KEY`).
  Con `OBJECT_STORE_CREATE_BUCKET=true`, el servicio crea el bucket `comondurismo-media` y lo deja
  de lectura pública. En producción se reemplaza por S3 (u otro): solo cambian las variables del
  servicio.

  ```bash
  docker compose up -d storage
  ```

## Datos y reinicio

Los datos viven en los volúmenes `postgres_data`, `redis_data` y `storage_data`. Para empezar de cero
(borra todo): `docker compose down -v`. Si cambias el nombre de esta carpeta o la mueves,
Docker Compose crea volúmenes nuevos y la base arranca vacía.

## Nota sobre PostGIS

El servicio de identidad no usa PostGIS; el de contenido (lugares, mapa, cercanía) sí. Por eso
la imagen es `postgis/postgis`.


## Gateway (nginx)

Un solo punto de entrada que reparte las peticiones a cada servicio según la ruta. Hoy no hay
dominio: se accede por `localhost` (o la IP del servidor) y todo lo que cambiará con el dominio
son variables del `.env` más un archivo de configuración.

```bash
docker compose up -d gateway
curl http://localhost:8000/gateway/health         # ok
curl http://localhost:8000/.well-known/jwks.json  # lo responde el servicio de identidad
```

| Ruta | Destino |
|---|---|
| `/api/v1/auth/*`, `/api/v1/users/*`, `/api/v1/roles/*`, `/api/v1/role-requests/*`, `/api/v1/admin/users/*`, `/.well-known/jwks.json` | Identidad (`comondurismo-identity:8080`) |
| `/gateway/health` | El propio gateway |
| `/api/v1/(categories\|subcategories\|services\|amenities\|operation-modes\|classifications\|places\|points-of-interest\|activities\|events\|guides\|businesses\|search\|map\|sync\|reports\|manage)/*` | Contenido (`comondurismo-content:8081`); la carga de archivos (`/api/v1/manage/<tipo>/<id>/media`) admite cuerpos de hasta 110 MB |
| `/media/*` | Archivos multimedia del almacenamiento de objetos (solo `GET` y `HEAD`) |
| cualquier otra | `404` JSON (aquí irá el frontend, ver abajo) |

Las rutas se pasan **sin cambiar** (no se quita ningún prefijo), así que el contrato de
`docs/api-auth.md` del servicio es el mismo con o sin gateway. `/health` de identidad no se
publica.

### Estructura

```
gateway/
  templates/default.conf.template   servidor (variables GATEWAY_* del .env)
  locations/10-identity.conf        rutas de identidad
  locations/30-content.conf         rutas de contenido (y carga de archivos)
  locations/40-media.conf           /media → almacenamiento de objetos
  locations/90-fallback.conf        404 para todo lo demás
  locations/20-frontend.conf.example  frontend detrás del gateway (opcional)
  snippets/proxy.conf               cabeceras comunes de proxy
  tls/https.conf.template.example   versión con HTTPS, para cuando haya dominio
```

### Agregar un servicio nuevo

El servicio de contenido ya está agregado (`locations/30-content.conf`); sirve de ejemplo.

1. Conéctalo a la red `comondurismo-network` (como ya hacen identidad y contenido).
2. Crea `gateway/locations/NN-nombre.conf`:

   ```nginx
   location ~ ^/api/v1/(rutas|del|servicio)(/|$) {
       set $servicio_upstream http://comondurismo-servicio:8082;
       proxy_pass $servicio_upstream;
       include /etc/nginx/snippets/proxy.conf;
   }
   ```
   Si algún `location` necesita un `client_max_body_size` mayor (carga de archivos), declárala
   **antes** del general: nginx usa la primera expresión regular que coincide, en orden.
3. `docker compose exec gateway nginx -t && docker compose exec gateway nginx -s reload`

Usa el nombre de **contenedor** (`container_name`) como host y deja la variable + `resolver`:
así el gateway arranca aunque el servicio esté caído. Elige prefijos de ruta que no choquen
con los de otro servicio.

### Qué configurar en identidad

- `TRUSTED_PROXIES=172.16.0.0/12` en su `.env` (la subred de Docker donde vive el gateway), para
  que el límite de peticiones use la IP real del cliente y no la del gateway. Sin esto, todos los
  clientes comparten la misma IP y el mismo contador.
- `CORS_ALLOWED_ORIGINS`: no cambia mientras el frontend corra en `localhost:5173`. Si el
  frontend se sirve desde el gateway (mismo origen) CORS deja de intervenir.

### Cuando tengas dominio

Nada de lo anterior se rehace; solo se activa HTTPS y cambian los valores:

1. **DNS**: registro A (y AAAA) de `api.tudominio.com` hacia la IP del servidor.
2. **`.env`**: `GATEWAY_SERVER_NAME=api.tudominio.com`, `GATEWAY_BIND=0.0.0.0`,
   `GATEWAY_HTTP_PORT=80`, `GATEWAY_HTTPS_PORT=443`.
3. **Certificado** (Let's Encrypt, gratuito, p. ej. con `certbot certonly --webroot -w /var/www/certbot`
   o `--standalone`). Deja `fullchain.pem` y `privkey.pem` en
   `gateway/certs/api.tudominio.com/` (la carpeta no se versiona).
4. **Configuración**: `cp gateway/tls/https.conf.template.example gateway/templates/default.conf.template`
   y en `compose.yml` descomenta el puerto 443 y el volumen `certs` (para el desafío ACME por
   webroot, monta también `/var/www/certbot`).
5. **Servicios**: en el `.env` de identidad cambia `EMAIL_VERIFICATION_URL`, `PASSWORD_RESET_URL`
   y `EMAIL_CHANGE_URL` a las URLs reales del frontend, y `CORS_ALLOWED_ORIGINS` a su origen
   `https://…`.
6. `docker compose up -d gateway`. Activa HSTS (ya viene en la plantilla) solo cuando HTTPS
   funcione bien.

Para varias cosas bajo un mismo dominio puedes usar subdominios (`api.`, `www.`) en vez de
rutas: añade un `server { server_name www.tudominio.com; … }` aparte; los `locations/` de la API
se mantienen.

**Mientras compras el dominio**: si ya tienes un servidor con IP pública, `sslip.io` /
`nip.io` dan un nombre real gratis (`203-0-113-5.sslip.io` → `203.0.113.5`), con el que Let's
Encrypt sí emite certificado. Sirve para probar HTTPS y correos con enlaces reales antes de
comprar el dominio.

> El puerto por defecto es `8000` y escucha solo en `127.0.0.1` para no chocar con otros
> programas de Windows (IIS, etc.) ni exponer nada por accidente.
