#!/usr/bin/env bash
# scripts/03_run_qemu.sh
# Arranca la VM vulnerable en QEMU (modo consola serial)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"


BZIMAGE="$BUILD_DIR/bzImage_vuln"
INITRAMFS="$BUILD_DIR/initramfs.cpio.gz"

# ID del estudiante para el hostname de la VM (anti-copia)
STUDENT_ID="${STUDENT_ID:-$(git config user.name 2>/dev/null | tr ' ' '-' | tr -cd '[:alnum:]-' | head -c 16)}"
STUDENT_ID="${STUDENT_ID:-unknown}"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

if [ ! -f "$BZIMAGE" ]; then
  echo -e "${RED}Error: $BZIMAGE no existe. Ejecuta primero: make kernel${NC}"
  exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
  echo -e "${RED}Error: $INITRAMFS no existe. Ejecuta primero: make rootfs${NC}"
  exit 1
fi

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Arrancando VM vulnerable — CVE-2026-31431                  ║${NC}"
echo -e "${GREEN}║  Salir de QEMU: Ctrl+A  luego  X                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  STUDENT_ID: ${CYAN}${STUDENT_ID}${NC}"
echo -e "  Kernel:     ${CYAN}${BZIMAGE}${NC}"
echo ""

exec qemu-system-x86_64 \
  -nographic \
  -no-reboot \
  -kernel "$BZIMAGE" \
  -initrd "$INITRAMFS" \
  -append "console=ttyS0 quiet STUDENT_ID=${STUDENT_ID}" \
  -m 512M \
  -smp "$(nproc)" \
  -enable-kvm 2>/dev/null || \
qemu-system-x86_64 \
  -nographic \
  -no-reboot \
  -kernel "$BZIMAGE" \
  -initrd "$INITRAMFS" \
  -append "console=ttyS0 quiet STUDENT_ID=${STUDENT_ID}" \
  -m 512M \
  -smp 2
