#!/usr/bin/env bash
# Compila con Docker la interfaz web de Comondurismo y deja los archivos estaticos en web/ de ESTE
# repositorio.
#
# Igual que con los binarios de los servicios: el servidor solo descarga el repositorio de
# infraestructura y no necesita Node ni el codigo fuente. La web se exporta aqui, en la maquina de
# desarrollo, a partir de un commit del repositorio Comondurismo-Web (clonado junto a este), y se
# versiona en web/dist/. La imagen "web" (Dockerfile) la sirve con nginx.
#
#   scripts/compilar-web.sh                  # exporta origin/main
#   REF=origin/beta scripts/compilar-web.sh  # otra rama, etiqueta o commit
#   scripts/compilar-web.sh --verificar      # solo comprueba web/dist con web/SHA256SUMS (sin Docker)
#
# Variables opcionales:
#   REPO_WEB              ruta del repositorio web (defecto ../Comondurismo-Web-App)
#   REF                   commit, rama o etiqueta a exportar (defecto origin/main). Se exporta con
#                         "git archive": NO toca la copia de trabajo ni la rama actual del repositorio.
#   EXPO_PUBLIC_API_URL   URL base de la API de identidad (defecto: la del codigo,
#                         https://comondurismo.cdconstitucion.tecnm.mx/api/v1)
#   EXPO_PUBLIC_CONTENT_API_URL  URL base de la API de contenido (defecto: la misma que la anterior)
#   PNPM_VERSION          version de pnpm (defecto 12.16.1)
#
# Las variables EXPO_PUBLIC_* se incrustan en el JavaScript al compilar: cambiar el dominio exige
# volver a compilar.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_WEB="${REPO_WEB:-../Comondurismo-Web-App}"
REF="${REF:-origin/main}"
PNPM_VERSION="${PNPM_VERSION:-12.16.1}"
NODE_IMAGEN="node:22-alpine"

DESTINO="web"
SUMAS="${DESTINO}/SHA256SUMS"
VERSION="${DESTINO}/VERSION"

error() { echo "ERROR: $*" >&2; exit 1; }
sin_cr() { tr -d '\r'; }

verificar() {
  [ -f "$SUMAS" ] || error "no existe $SUMAS: compila primero con scripts/compilar-web.sh"
  (cd "$DESTINO" && sha256sum --quiet -c SHA256SUMS) && echo "web/dist: OK"
}

if [ "${1:-}" = "--verificar" ]; then
  verificar
  exit 0
fi

command -v docker >/dev/null || error "Docker no esta instalado o no esta en el PATH"
docker info >/dev/null 2>&1 || error "el motor de Docker no esta encendido"
[ -d "$REPO_WEB/.git" ] || error "no encuentro el repositorio web en $REPO_WEB (ajusta REPO_WEB)"

# Si REF es una rama remota, se trae lo ultimo antes de exportar.
case "$REF" in
  origin/*) git -C "$REPO_WEB" fetch --quiet origin ;;
esac
commit="$(git -C "$REPO_WEB" rev-parse --short=12 "${REF}^{commit}")" || error "no existe la referencia '$REF' en $REPO_WEB"

trabajo="$(mktemp -d "tmp-web-XXXXXX")"
trap 'rm -rf "$trabajo"' EXIT
mkdir -p "$trabajo/fuente" "$trabajo/salida"

echo "==> Exportando $REF ($commit) de $REPO_WEB ..."
git -C "$REPO_WEB" archive --format=tar "$commit" | tar -x -C "$trabajo/fuente"

# El Dockerfile de compilacion va por stdin: el contexto es solo el codigo exportado.
echo "==> Compilando la web con $NODE_IMAGEN y pnpm $PNPM_VERSION ..."
docker build --platform linux/amd64 \
  --build-arg "PNPM_VERSION=${PNPM_VERSION}" \
  --build-arg "EXPO_PUBLIC_API_URL=${EXPO_PUBLIC_API_URL:-}" \
  --build-arg "EXPO_PUBLIC_CONTENT_API_URL=${EXPO_PUBLIC_CONTENT_API_URL:-}" \
  --target dist --output "type=local,dest=${trabajo}/salida" \
  -f - "$trabajo/fuente" <<EOF
# syntax=docker/dockerfile:1
FROM ${NODE_IMAGEN} AS compilar
ARG PNPM_VERSION
RUN npm install -g pnpm@\${PNPM_VERSION}
WORKDIR /app
COPY . .
ENV CI=1 EXPO_NO_TELEMETRY=1
RUN pnpm install --frozen-lockfile
ARG EXPO_PUBLIC_API_URL
ARG EXPO_PUBLIC_CONTENT_API_URL
# Una variable vacia no debe pisar el valor por defecto del codigo (usa "??", no "||").
RUN [ -n "\$EXPO_PUBLIC_API_URL" ] || unset EXPO_PUBLIC_API_URL; \\
    [ -n "\$EXPO_PUBLIC_CONTENT_API_URL" ] || unset EXPO_PUBLIC_CONTENT_API_URL; \\
    pnpm exec expo export --platform web --output-dir /dist

FROM scratch AS dist
COPY --from=compilar /dist/ /
EOF

[ -s "$trabajo/salida/index.html" ] || error "la compilacion no produjo index.html"

rm -rf "${DESTINO:?}/dist"
mkdir -p "$DESTINO"
cp -R "$trabajo/salida" "${DESTINO}/dist"

# Hashes de todos los archivos, con rutas relativas a web/ y saltos de linea LF.
(cd "$DESTINO" && find dist -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
  | sed -E 's#^([0-9a-f]{64}) [ *]#\1  #' | sin_cr) > "$SUMAS.tmp"
mv "$SUMAS.tmp" "$SUMAS"

printf 'web commit=%s ref=%s compilado=%s base=%s pnpm=%s api=%s\n' \
  "$commit" "$REF" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NODE_IMAGEN" "$PNPM_VERSION" \
  "${EXPO_PUBLIC_API_URL:-por-defecto}" | sin_cr > "$VERSION"

echo "==> Verificando web/ ..."
verificar

echo
echo "Listo: web/dist ($(find "${DESTINO}/dist" -type f | wc -l | tr -d ' ') archivos, commit $commit)."
echo "Revisa con 'git status' y versiona con: git add web && git commit"
