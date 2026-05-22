#!/usr/bin/env bash
# scripts/01_build_kernel.sh
# Descarga y compila el kernel Linux v6.12 (anterior al parche a664bf3d603d)
# El módulo algif_aead estará habilitado → vulnerable a CVE-2026-31431
set -euo pipefail

KERNEL_TAG="${KERNEL_TAG:-v6.12}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}[1/5] Clonando kernel ${KERNEL_TAG} (solo último commit)...${NC}"
if [ ! -d "$KERNEL_SRC" ]; then
  git clone --depth 1 \
    --branch "$KERNEL_TAG" \
    https://github.com/torvalds/linux.git \
    "$KERNEL_SRC"
else
  echo -e "${YELLOW}  → Fuentes ya presentes, omitiendo clone.${NC}"
fi

cd "$KERNEL_SRC"
echo ""
echo -e "${CYAN}[2/5] Guardando hash del commit vulnerable (evidencia)...${NC}"
VULN_HASH=$(git rev-parse HEAD)
echo "$VULN_HASH" > /workspaces/copy-fail-challenge/kernel/vuln_commit.txt
echo "  Hash: $VULN_HASH"

echo ""
echo -e "${CYAN}[3/5] Configurando el kernel (tiny + algif_aead habilitado)...${NC}"
# Partimos de tiny config y habilitamos lo mínimo para QEMU + el módulo vulnerable
make tinyconfig

# Soporte 64-bit
scripts/config --enable 64BIT
# Consola serie (para QEMU -nographic)
scripts/config --enable SERIAL_8250
scripts/config --enable SERIAL_8250_CONSOLE
scripts/config --enable TTY
# Sistema de archivos en memoria (initramfs)
scripts/config --enable BLK_DEV_INITRD
scripts/config --enable INITRAMFS_SOURCE
scripts/config --enable TMPFS
# Módulo del socket de red (AF_UNIX, AF_ALG)
scripts/config --enable NET
scripts/config --enable UNIX
scripts/config --enable INET
# ── LA PIEZA CLAVE: API crypto expuesta a userspace ──────────────────────────
scripts/config --enable CRYPTO
scripts/config --enable CRYPTO_USER_API        # AF_ALG base
scripts/config --enable CRYPTO_USER_API_AEAD   # algif_aead  ← VULNERABLE
scripts/config --enable CRYPTO_USER_API_SKCIPHER
scripts/config --enable CRYPTO_AUTHENCESN      # el template que escribe de más
scripts/config --enable CRYPTO_AES
scripts/config --enable CRYPTO_CBC
scripts/config --enable CRYPTO_HMAC
scripts/config --enable CRYPTO_SHA256
# Setuid binaries (necesario para la escalada de privilegios)
scripts/config --enable MULTIUSER
# Misc necesario
scripts/config --enable PRINTK
scripts/config --enable EARLY_PRINTK
scripts/config --enable PROC_FS
scripts/config --enable SYSFS
scripts/config --enable DEVTMPFS
scripts/config --enable DEVTMPFS_MOUNT
scripts/config --enable RD_GZIP        # descomprimir initramfs gzip
scripts/config --enable BINFMT_ELF     # ejecutar binarios ELF (BusyBox)
scripts/config --enable BINFMT_SCRIPT  # ejecutar scripts de shell (init)

make olddefconfig

echo ""
echo -e "${CYAN}[4/5] Compilando kernel con ${JOBS} cores (esto toma ~15-25 min)...${NC}"
echo -e "${YELLOW}  Tip: puedes abrir otra terminal y leer el write-up mientras compila.${NC}"
START=$(date +%s)
make -j"$JOBS" bzImage 2>&1 | tail -5
END=$(date +%s)
echo -e "  Tiempo de compilación: $((END - START)) segundos"

mkdir -p "$BUILD_DIR"
cp arch/x86/boot/bzImage "$BUILD_DIR/bzImage_vuln"
echo ""
echo -e "${GREEN}[5/5] ✓ Kernel vulnerable compilado → kernel/build/bzImage_vuln${NC}"
echo ""

# Verificar que algif_aead está habilitado en la config
if grep -q "CONFIG_CRYPTO_USER_API_AEAD=y" .config; then
  echo -e "${GREEN}  ✓ CONFIG_CRYPTO_USER_API_AEAD=y confirmado en .config${NC}"
else
  echo -e "${YELLOW}  ⚠ Verifica manualmente que CONFIG_CRYPTO_USER_API_AEAD esté habilitado${NC}"
fi

echo ""
echo -e "  Siguiente paso: ${CYAN}make rootfs${NC}"
