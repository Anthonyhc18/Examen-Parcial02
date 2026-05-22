#!/usr/bin/env bash
# scripts/00_fetch_kernel.sh
# Descarga el bzImage pre-compilado del GitHub Release del docente.
# Mucho más rápido que compilar desde fuente (~2 min vs ~25 min).
#
# Estrategias en orden de prioridad:
#   1. GitHub CLI  (gh release download)        → más fiable, usa auth automática
#   2. curl + GitHub API                         → no requiere CLI instalada
#   3. wget directo si se conoce la URL exacta  → fallback sin auth
#
# Si todas fallan → instruye al estudiante a compilar con make kernel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
MANIFEST_FILE="$BUILD_DIR/kernel-manifest.json"

# ── Configuración: el docente debe actualizar estos valores ──────────────────
# REPO: organización/nombre-del-repo donde está el Release
# RELEASE_TAG: el tag del Release creado por el workflow build-kernel-image.yml
REPO="${KERNEL_REPO:-}"        # ej: "mi-org/copy-fail-challenge"
RELEASE_TAG="${KERNEL_RELEASE_TAG:-kernel-v6.12-vuln}"
BZIMAGE_ASSET="bzImage_vuln"

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

# ── Detectar REPO si no está configurado ──────────────────────────────────────
if [ -z "$REPO" ]; then
  # Intentar detectar del origen git del repo actual
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  if echo "$REMOTE_URL" | grep -q "github.com"; then
    REPO=$(echo "$REMOTE_URL" \
      | sed -E 's|.*github\.com[:/]||' \
      | sed 's|\.git$||')
  fi
fi

if [ -z "$REPO" ]; then
  echo -e "${RED}Error: No se pudo detectar el repositorio GitHub.${NC}"
  echo "Configura la variable de entorno:"
  echo "  export KERNEL_REPO='tu-org/copy-fail-challenge'"
  echo "  make fetch-kernel"
  exit 1
fi

echo -e "${CYAN}Repositorio: ${REPO}${NC}"
echo -e "${CYAN}Release:     ${RELEASE_TAG}${NC}"
echo ""

mkdir -p "$BUILD_DIR"

# ── Verificar si ya existe el bzImage ─────────────────────────────────────────
if [ -f "$BUILD_DIR/$BZIMAGE_ASSET" ]; then
  SIZE=$(du -sh "$BUILD_DIR/$BZIMAGE_ASSET" | cut -f1)
  echo -e "${GREEN}✓ bzImage ya presente ($SIZE) — omitiendo descarga.${NC}"
  echo -e "  Usa ${CYAN}make kernel${NC} si quieres recompilar desde fuente."
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# ESTRATEGIA 1: GitHub CLI
# ══════════════════════════════════════════════════════════════════════════════
try_gh_cli() {
  if ! command -v gh &>/dev/null; then
    echo -e "${YELLOW}  [gh CLI] No instalado, intentando siguiente método...${NC}"
    return 1
  fi

  echo -e "${CYAN}[1/3] Intentando descarga con GitHub CLI (gh)...${NC}"
  
  if gh release download "$RELEASE_TAG" \
       --repo "$REPO" \
       --pattern "$BZIMAGE_ASSET" \
       --dir "$BUILD_DIR" \
       --clobber 2>/dev/null; then
    
    # También descargar el manifest si existe
    gh release download "$RELEASE_TAG" \
      --repo "$REPO" \
      --pattern "kernel-manifest.json" \
      --dir "$BUILD_DIR" \
      --clobber 2>/dev/null || true
    
    return 0
  fi
  
  echo -e "${YELLOW}  [gh CLI] Falló, intentando siguiente método...${NC}"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# ESTRATEGIA 2: curl + GitHub API
# ══════════════════════════════════════════════════════════════════════════════
try_curl_api() {
  echo -e "${CYAN}[2/3] Intentando descarga via GitHub API + curl...${NC}"
  
  # Obtener la URL del asset via la API
  API_URL="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}"
  
  # Headers: añadir token si está disponible
  HEADERS=(-H "Accept: application/vnd.github+json")
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    HEADERS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  
  RELEASE_JSON=$(curl -fsSL "${HEADERS[@]}" "$API_URL" 2>/dev/null) || {
    echo -e "${YELLOW}  [API] No se pudo obtener info del release${NC}"
    return 1
  }
  
  # Extraer URL de descarga del asset bzImage_vuln
  DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
for a in assets:
    if a['name'] == '${BZIMAGE_ASSET}':
        print(a['browser_download_url'])
        break
" 2>/dev/null)

  if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${YELLOW}  [API] Asset '${BZIMAGE_ASSET}' no encontrado en el release${NC}"
    return 1
  fi
  
  echo "  URL: $DOWNLOAD_URL"
  
  if curl -fL \
       --progress-bar \
       "${HEADERS[@]}" \
       -o "$BUILD_DIR/$BZIMAGE_ASSET" \
       "$DOWNLOAD_URL"; then
    
    # También descargar el manifest
    MANIFEST_URL=$(echo "$RELEASE_JSON" \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if a['name'] == 'kernel-manifest.json':
        print(a['browser_download_url'])
        break
" 2>/dev/null)
    [ -n "$MANIFEST_URL" ] && \
      curl -fsSL "$MANIFEST_URL" -o "$MANIFEST_FILE" 2>/dev/null || true
    
    return 0
  fi
  
  echo -e "${YELLOW}  [curl API] Descarga falló${NC}"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# ESTRATEGIA 3: wget con URL directa (hardcoded por el docente)
# ══════════════════════════════════════════════════════════════════════════════
try_wget_direct() {
  # El docente puede copiar la URL directa del Release aquí
  DIRECT_URL="${KERNEL_DIRECT_URL:-}"
  
  if [ -z "$DIRECT_URL" ]; then
    # Construir URL canónica de GitHub Releases
    DIRECT_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${BZIMAGE_ASSET}"
  fi
  
  echo -e "${CYAN}[3/3] Intentando descarga directa con wget...${NC}"
  echo "  URL: $DIRECT_URL"
  
  if wget -q --show-progress \
       -O "$BUILD_DIR/$BZIMAGE_ASSET" \
       "$DIRECT_URL" 2>/dev/null || \
     wget -q --show-progress \
       --no-check-certificate \
       -O "$BUILD_DIR/$BZIMAGE_ASSET" \
       "$DIRECT_URL" 2>/dev/null; then
    return 0
  fi
  
  echo -e "${YELLOW}  [wget] Descarga falló${NC}"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# EJECUTAR ESTRATEGIAS EN ORDEN
# ══════════════════════════════════════════════════════════════════════════════
SUCCESS=false

for strategy in try_gh_cli try_curl_api try_wget_direct; do
  if $strategy; then
    SUCCESS=true
    break
  fi
done

# ── Resultado ─────────────────────────────────────────────────────────────────
if $SUCCESS && [ -f "$BUILD_DIR/$BZIMAGE_ASSET" ]; then
  SIZE=$(du -sh "$BUILD_DIR/$BZIMAGE_ASSET" | cut -f1)
  SHA256=$(sha256sum "$BUILD_DIR/$BZIMAGE_ASSET" | cut -d' ' -f1)
  
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ bzImage descargado exitosamente${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════${NC}"
  echo -e "  Tamaño:  $SIZE"
  echo -e "  SHA256:  $SHA256"
  
  # Guardar manifest si no se descargó
  if [ ! -f "$MANIFEST_FILE" ]; then
    cat > "$MANIFEST_FILE" << EOF
{
  "kernel_tag": "downloaded",
  "release_tag": "${RELEASE_TAG}",
  "repo": "${REPO}",
  "sha256_bzimage": "${SHA256}",
  "downloaded_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  else
    echo ""
    echo "  Manifest del kernel:"
    python3 -m json.tool "$MANIFEST_FILE" 2>/dev/null || cat "$MANIFEST_FILE"
  fi
  
  echo ""
  echo -e "  Siguiente paso: ${CYAN}make rootfs${NC}  (~3-5 min)"
  echo -e "  Luego:          ${CYAN}make qemu${NC}"

else
  # ── Todas las estrategias fallaron → instrucciones de fallback ──────────────
  echo ""
  echo -e "${RED}════════════════════════════════════════════════${NC}"
  echo -e "${RED}  No se pudo descargar el bzImage pre-compilado${NC}"
  echo -e "${RED}════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Posibles causas:"
  echo "  1. El Release '$RELEASE_TAG' no existe en '$REPO'"
  echo "  2. El repositorio es privado y no tienes acceso"
  echo "  3. Sin conexión a internet"
  echo ""
  echo -e "${YELLOW}  Opciones:${NC}"
  echo ""
  echo "  A) Autenticar con GitHub CLI y reintentar:"
  echo "     gh auth login"
  echo "     make fetch-kernel"
  echo ""
  echo "  B) El docente te comparte la URL directa:"
  echo "     KERNEL_DIRECT_URL='https://...' make fetch-kernel"
  echo ""
  echo "  C) Compilar desde fuente (toma ~20-25 min):"
  echo "     make kernel"
  echo ""
  exit 1
fi
