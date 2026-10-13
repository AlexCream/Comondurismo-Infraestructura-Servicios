#!/usr/bin/env bash
# Compila con Docker los servicios de Comondurismo y deja los binarios en bin/ de ESTE repositorio.
#
# El servidor solo descarga el repositorio de infraestructura: no necesita el codigo fuente ni
# Go. Los binarios se compilan aqui, en la maquina de desarrollo, a partir de los repositorios de
# cada servicio (clonados junto a este), y se versionan en bin/linux-<arquitectura>/.
#
#   scripts/compilar-binarios.sh                 # identidad y contenido, linux/amd64
#   scripts/compilar-binarios.sh identidad       # solo uno (identidad | contenido)
#   ARQUITECTURA=arm64 scripts/compilar-binarios.sh
#   scripts/compilar-binarios.sh --verificar     # solo comprueba bin/ con SHA256SUMS (sin Docker)
#
# Variables opcionales:
#   REPO_IDENTIDAD   ruta del repositorio de identidad  (defecto ../Comondurismo-Api-Identidad)
#   REPO_CONTENIDO   ruta del repositorio de contenido  (defecto ../Comondurismo-Api-Contenido)
#   ARQUITECTURA     amd64 (defecto) o arm64
#   PERMITIR_CAMBIOS=1  compila aunque el repositorio del servicio tenga cambios sin commit
#
# Git Bash en Windows: este script no usa rutas absolutas dentro de los comandos de Docker, asi
# que no necesita MSYS_NO_PATHCONV.
set -euo pipefail

cd "$(dirname "$0")/.."

ARQUITECTURA="${ARQUITECTURA:-amd64}"
REPO_IDENTIDAD="${REPO_IDENTIDAD:-../Comondurismo-Api-Identidad}"
REPO_CONTENIDO="${REPO_CONTENIDO:-../Comondurismo-Api-Contenido}"

DESTINO="bin/linux-${ARQUITECTURA}"
SUMAS="${DESTINO}/SHA256SUMS"
VERSION="${DESTINO}/VERSION"

# nombre corto -> carpeta dentro de bin/ , repositorio, binarios esperados
declare -A REPO=( [identidad]="$REPO_IDENTIDAD" [contenido]="$REPO_CONTENIDO" )
declare -A CARPETA=( [identidad]="identity" [contenido]="content" )
declare -A ESPERADOS=(
  [identidad]="api migrate genkey grantrole healthcheck"
  [contenido]="api migrate healthcheck"
)

error() { echo "ERROR: $*" >&2; exit 1; }

verificar() {
  [ -f "$SUMAS" ] || error "no existe $SUMAS: compila primero con scripts/compilar-binarios.sh"
  (cd "$DESTINO" && sha256sum -c SHA256SUMS)
}

if [ "${1:-}" = "--verificar" ]; then
  verificar
  exit 0
fi

SERVICIOS=("${1:-todos}")
if [ "${SERVICIOS[0]}" = "todos" ]; then
  SERVICIOS=(identidad contenido)
fi

command -v docker >/dev/null || error "Docker no esta instalado o no esta en el PATH"
docker info >/dev/null 2>&1 || error "el motor de Docker no esta encendido"

mkdir -p "$DESTINO" env
touch "$SUMAS" "$VERSION"

# Git Bash en Windows puede escribir saltos de linea CRLF; en Linux romperian "sha256sum -c"
# (el nombre del archivo incluiria el \r). Todo lo que se genera aqui debe quedar con LF.
sin_cr() { tr -d '\r'; }

# Quita de un archivo las lineas que contienen un texto fijo.
quitar_lineas() { # archivo texto
  local tmp; tmp="$(mktemp)"
  grep -v -F -- "$2" "$1" > "$tmp" || true
  cat "$tmp" > "$1"
  rm -f "$tmp"
}

for svc in "${SERVICIOS[@]}"; do
  [ -n "${REPO[$svc]:-}" ] || error "servicio desconocido '$svc' (usa: identidad | contenido)"
  repo="${REPO[$svc]}"
  carpeta="${CARPETA[$svc]}"

  [ -f "$repo/Dockerfile" ] || error "no encuentro $repo/Dockerfile (ajusta REPO_IDENTIDAD / REPO_CONTENIDO)"
  grep -q "AS binaries" "$repo/Dockerfile" || error "el Dockerfile de $repo no tiene la etapa 'binaries'; actualiza ese repositorio"

  commit="$(git -C "$repo" rev-parse --short=12 HEAD)"
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    [ "${PERMITIR_CAMBIOS:-0}" = "1" ] || error "$repo tiene cambios sin commit: los binarios no corresponderian a ningun commit. Haz commit, o usa PERMITIR_CAMBIOS=1 solo para pruebas."
    commit="${commit}-con-cambios"
  fi

  echo "==> Compilando $svc ($commit) para linux/${ARQUITECTURA} ..."
  salida="$(mktemp -d "tmp-bin-XXXXXX")"
  trap 'rm -rf "$salida"' EXIT

  docker build --platform "linux/${ARQUITECTURA}" --target binaries \
    --output "type=local,dest=${salida}" "$repo"

  for b in ${ESPERADOS[$svc]}; do
    [ -s "${salida}/${b}" ] || error "la compilacion de $svc no produjo '$b'"
  done

  # Hashes nuevos y anteriores de este servicio.
  # sha256sum puede escribir "hash *archivo" (modo binario, Git Bash); se normaliza a "hash  archivo".
  nuevos="$(cd "$salida" && sha256sum ${ESPERADOS[$svc]} | sed -E "s#^([0-9a-f]{64}) [ *]#\1  ${carpeta}/#" | sin_cr | sort -k2)"
  previos="$(grep -F -- "  ${carpeta}/" "$SUMAS" | sin_cr | sort -k2 || true)"

  if [ "$nuevos" = "$previos" ]; then
    echo "    sin cambios: los binarios de $svc son identicos a los que ya estan en $DESTINO/${carpeta}"
  else
    rm -rf "${DESTINO:?}/${carpeta}"
    mkdir -p "${DESTINO}/${carpeta}"
    for b in ${ESPERADOS[$svc]}; do
      cp "${salida}/${b}" "${DESTINO}/${carpeta}/${b}"
      chmod 0755 "${DESTINO}/${carpeta}/${b}" 2>/dev/null || true
    done
    quitar_lineas "$SUMAS" "  ${carpeta}/"
    printf '%s\n' "$nuevos" >> "$SUMAS"
    sort -k2 "$SUMAS" -o "$SUMAS"

    quitar_lineas "$VERSION" "${carpeta} "
    printf '%s commit=%s compilado=%s arquitectura=%s base=golang:1.26-alpine\n' \
      "$carpeta" "$commit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ARQUITECTURA" >> "$VERSION"
    sort "$VERSION" -o "$VERSION"
    sin_cr < "$VERSION" > "$VERSION.tmp" && mv "$VERSION.tmp" "$VERSION"
    sin_cr < "$SUMAS" > "$SUMAS.tmp" && mv "$SUMAS.tmp" "$SUMAS"
    echo "    actualizado: $DESTINO/${carpeta}"
  fi

  # La plantilla de variables viaja con los binarios, para que el repositorio sea autosuficiente.
  if [ -f "$repo/.env.example" ]; then
    cp "$repo/.env.example" "env/${carpeta}.env.example"
  fi

  rm -rf "$salida"
  trap - EXIT
done

# Normaliza los archivos de metadatos aunque no haya cambios en los binarios.
for f in "$SUMAS" "$VERSION"; do
  sin_cr < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

echo "==> Verificando bin/ ..."
verificar

echo
echo "Listo. Revisa los cambios con 'git status' y 'git diff --stat'; los binarios nuevos se"
echo "versionan como cualquier archivo (git add bin env && git commit)."
