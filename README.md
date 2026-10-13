# Comondurismo - Despliegue (infraestructura + servicios)

**Es el único repositorio que se descarga en el servidor.** Levanta todo el sistema con
`docker compose`: PostgreSQL/PostGIS, Redis, almacenamiento de objetos (S3), el servicio de
identidad y el servicio de contenido.

Aquí **no hay código fuente**: los servicios viajan como **binarios ya compilados** en `bin/`, y la
imagen de cada contenedor se arma copiándolos a una base mínima (`Dockerfile`, sin compilador).
Los binarios se generan con Docker en la máquina de desarrollo (`scripts/compilar-binarios.sh`).

```
bin/linux-amd64/       binarios estáticos (identity/ y content/) + SHA256SUMS + VERSION
env/                   plantillas de configuración de cada servicio (se copian a *.env)
scripts/               compilar-binarios.sh
postgres/initdb/       crea la base de contenido la primera vez
Dockerfile             imágenes identity y content a partir de bin/ (verifica los hashes)
compose.yml            todo el sistema
```

> **Nginx no está aquí**: no es un servicio de Comondurismo. Lo configura el administrador del
> servidor (nota `Despliegue_y_Nginx` de la bóveda de Obsidian). Los servicios solo escuchan en
> `127.0.0.1`; el rango de puertos del proyecto es **50300–50400** (nota `Puertos_y_Red`).

---

## En el servidor: primera puesta en marcha

Requisitos: Linux x86-64 con Docker y el plugin `docker compose`, y `git`. No se necesita Go.

```bash
git clone --depth 1 https://github.com/AlexCream/Comondurismo-Infraestructura-Servicios.git
cd Comondurismo-Infraestructura-Servicios

# 1. Configuración (los .env no se versionan)
cp .env.example .env                              # contraseñas de PostgreSQL y Redis, llaves S3
cp env/identity.env.example env/identity.env      # identidad: CORS, enlaces de correo, SMTP...
cp env/content.env.example  env/content.env       # contenido: CORS, MEDIA_PUBLIC_BASE_URL...
mkdir -p secrets

# 2. Construir las imágenes (copia los binarios de bin/ y comprueba sus hashes)
docker compose build

# 3. Clave de firma de tokens (UNA vez; respáldala como una contraseña)
docker compose run --rm -T --no-deps identity /genkey > secrets/jwt-private.pem
chmod 644 secrets/jwt-private.pem                 # el contenedor corre como uid 65532

# 4. Infraestructura, migraciones y servicios
docker compose up -d postgres redis storage
docker compose run --rm identity /migrate up
docker compose run --rm content  /migrate up
docker compose up -d

# 5. Primer administrador (el usuario debe estar registrado)
docker compose run --rm identity /grantrole -email correo@ejemplo.com -role ADMINISTRATOR

# 6. Comprobar (por el propio servidor; el acceso externo lo da nginx)
curl http://127.0.0.1:50310/health && curl http://127.0.0.1:50311/health
docker compose ps
```

> ⚠️ **Crea `secrets/jwt-private.pem` ANTES de `docker compose up`.** Si el archivo no existe,
> Docker crea una *carpeta* con ese nombre y identidad no arranca (`is a directory`).

**Qué configurar** (cada variable está descrita en su plantilla):

| Dónde | Qué |
|---|---|
| `.env` | `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` (únicos para este servidor; contraseñas alfanuméricas para no tener que codificar la URL). Con bases administradas: `IDENTITY_DATABASE_URL`, `CONTENT_DATABASE_URL` |
| `env/identity.env` | `CORS_ALLOWED_ORIGINS`, `EMAIL_VERIFICATION_URL`, `PASSWORD_RESET_URL`, `EMAIL_CHANGE_URL`, `EMAIL_MEDIA_BASE_URL`, `SMTP_*`, `TRUSTED_PROXIES=172.16.0.0/12` |
| `env/content.env` | `CORS_ALLOWED_ORIGINS`, `MEDIA_PUBLIC_BASE_URL`, `TRUSTED_PROXIES=172.16.0.0/12`, `OBJECT_STORE_CREATE_BUCKET=false` en producción |

La conexión a PostgreSQL, Redis, el almacenamiento y el JWKS de identidad **se fijan en el
`compose.yml` a partir de `.env`** (tienen prioridad sobre los `env/*.env`): las contraseñas se
escriben una sola vez. Los valores que dependen del dominio están listados en `Despliegue_y_Nginx`.

## Actualizar a una versión nueva

```bash
git pull
docker compose build
docker compose run --rm identity /migrate up      # y content, si cambió
docker compose run --rm content  /migrate up
docker compose up -d                              # recrea solo lo que cambió
```

`bin/linux-amd64/VERSION` dice de qué commit de cada servicio salió el binario desplegado.
**Regresar a la versión anterior:** `git checkout <commit-anterior> -- bin env/*.example`,
`docker compose build && docker compose up -d` (si hubo migraciones, restaura el respaldo de la base).

---

## En desarrollo: compilar los binarios

Los repositorios de los servicios (`Comondurismo-Api-Identidad`, `Comondurismo-Api-Contenido`) van
clonados junto a este. Con Docker encendido:

```bash
scripts/compilar-binarios.sh                  # identidad y contenido, linux/amd64
scripts/compilar-binarios.sh identidad        # solo uno
scripts/compilar-binarios.sh --verificar      # comprueba bin/ con SHA256SUMS (sin Docker)
ARQUITECTURA=arm64 scripts/compilar-binarios.sh
```

- Compila con `docker build --target binaries` de cada servicio (Go 1.26, estático, `-trimpath`):
  el resultado es **reproducible** (mismo código ⇒ mismos hashes) y no depende de la máquina.
- **Exige que el repositorio del servicio no tenga cambios sin commit**: así `VERSION` apunta a un
  commit real. (`PERMITIR_CAMBIOS=1` lo salta, solo para pruebas.)
- Si el binario no cambió, no toca nada (no engorda el repositorio).
- Actualiza `bin/`, `SHA256SUMS`, `VERSION` y `env/*.env.example` (copia de la plantilla de cada
  servicio). Después: `git add bin env && git commit`.

> **Tamaño:** los binarios pesan ~80 MB en conjunto y cada versión nueva los agrega al historial.
> En el servidor usa `git clone --depth 1`. Si crece demasiado, mover `bin/` a Git LFS o a releases
> de GitHub no cambia el resto del flujo.

## Desarrollo sin binarios

Cada servicio tiene su propio `compose.yml` para desarrollar con el código (`docker compose up -d
--build` en su repositorio). **No lo combines con este compose**: ambos usan los nombres de
contenedor `comondurismo-identity` y `comondurismo-content`. Mailpit (correo falso) solo se levanta
con `docker compose --profile dev up -d`.

## Puertos (rango de Comondurismo: 50300–50400)

| Pieza | En la red de Docker | En el servidor | Variable |
|---|---|---|---|
| PostgreSQL | `postgres:5432` | `127.0.0.1:50300` | `POSTGRES_PORT` |
| Redis | `redis:6379` | `127.0.0.1:50301` | `REDIS_PORT` |
| Mailpit (solo `--profile dev`) | `mailpit:1025` / `8025` | `127.0.0.1:50302` / `50303` | `MAILPIT_*_PORT` |
| Almacenamiento S3 (API / consola) | `storage:9000` / `9001` | `127.0.0.1:50304` / `50305` | `S3_API_PORT`, `S3_CONSOLE_PORT` |
| Identidad | `comondurismo-identity:50310` | `127.0.0.1:50310` | `IDENTITY_PORT` |
| Contenido | `comondurismo-content:50311` | `127.0.0.1:50311` | `CONTENT_PORT` |

`BIND_ADDRESS` (servicios) y `S3_BIND_ADDRESS` (API S3) abren esos puertos a toda la red con
`0.0.0.0`: solo para pruebas en un laboratorio, nunca en producción. En Windows, el sistema puede
tener reservado parte del rango (`forbidden by its access permissions`): ver `Puertos_y_Red`.

## Datos y reinicio

Los datos viven en los volúmenes `postgres_data`, `redis_data` y `storage_data`. Empezar de cero
(**borra todo**, incluidos los archivos subidos): `docker compose down -v`. Si cambias el nombre de la
carpeta, Compose crea volúmenes nuevos y la base arranca vacía.

## Documentación

En la bóveda de Obsidian (`Comondurismo-Documentacion-Obsidian/Comondurismo/Servicios/`):
`Arquitectura_de_Servicios`, `Despliegue_con_Binarios`, `Despliegue_y_Nginx`, `Puertos_y_Red`,
`Infraestructura_Desarrollo`, y las notas de cada servicio.
