#!/usr/bin/env bash
# scripts/04_build_patched_kernel.sh
# Aplica el parche de CVE-2026-31431 y recompila el kernel
# El parche revierte la optimización in-place de algif_aead.c (commit 72548b093ee3)
# introducida en 2017, que es la raíz del bug.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"

KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"

PATCH_FILE="$WORKSPACE_ROOT/patches/fix_algif_aead.patch"
JOBS=$(nproc)

GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -d "$KERNEL_SRC" ]; then
  echo -e "${RED}Error: Fuentes del kernel no encontradas. Ejecuta primero: make kernel${NC}"
  exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo -e "${RED}Error: patches/fix_algif_aead.patch no existe.${NC}"
  echo ""
  echo -e "${YELLOW}Tu tarea (Hito 4):${NC}"
  echo "  1. Estudia el write-up técnico del CVE (CHALLENGE.md sección 4)"
  echo "  2. Identifica la función incorrecta en crypto/algif_aead.c"
  echo "  3. Crea el parche en patches/fix_algif_aead.patch"
  echo "     El fix oficial es el commit a664bf3d603d del mainline."
  echo "     Pista: la función _aead_recvmsg() no debe pasar las páginas"
  echo "     del TX SGL como destino de escritura."
  echo ""
  echo -e "  Puedes usar: ${CYAN}git -C $KERNEL_SRC diff HEAD patches/fix_algif_aead.patch${NC}"
  echo -e "  O cherry-pick del upstream (requiere git fetch con historial completo)"
  exit 1
fi

cd "$KERNEL_SRC"

echo -e "${CYAN}[1/4] Verificando estado del repositorio...${NC}"
git status --short

echo ""
echo -e "${CYAN}[2/4] Aplicando parche de seguridad...${NC}"
if git apply --check "$PATCH_FILE" 2>/dev/null; then
  git apply "$PATCH_FILE"
  echo -e "${GREEN}  ✓ Parche aplicado exitosamente${NC}"
else
  echo -e "${YELLOW}  El parche ya podría estar aplicado o hay conflictos.${NC}"
  echo -e "  Verifica con: git diff crypto/algif_aead.c"
fi

# Guardar hash del commit parcheado
PATCH_HASH=$(git stash 2>/dev/null && git rev-parse HEAD || git rev-parse HEAD)
echo "$PATCH_HASH" > "$BUILD_DIR/patched_commit.txt"

echo ""
echo -e "${CYAN}[3/4] Compilando kernel parcheado...${NC}"
START=$(date +%s)
make -j"$JOBS" bzImage 2>&1 | tail -5
END=$(date +%s)
echo -e "  Tiempo: $((END - START)) segundos"

cp arch/x86/boot/bzImage "$BUILD_DIR/bzImage_patched"
echo -e "${GREEN}  ✓ Kernel parcheado → kernel/build/bzImage_patched${NC}"

echo ""
echo -e "${CYAN}[4/4] Reconstruyendo initramfs con kernel parcheado...${NC}"
cd /workspaces/copy-fail-challenge
BZIMAGE_BACKUP="$BUILD_DIR/bzImage_vuln"
cp "$BUILD_DIR/bzImage_patched" "$BUILD_DIR/bzImage_vuln"
bash scripts/02_build_rootfs.sh
cp "$BUILD_DIR/bzImage_vuln" "$BUILD_DIR/bzImage_patched"
mv "$BZIMAGE_BACKUP" "$BUILD_DIR/bzImage_vuln"

echo ""
echo -e "${GREEN}✓ Todo listo. Para verificar que el exploit falla:${NC}"
echo -e "  ${CYAN}KERNEL=patched make qemu-patched${NC}"
echo ""
echo -e "Luego documenta en evidence/hito4_patched.txt"
