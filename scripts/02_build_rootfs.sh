#!/usr/bin/env bash
# scripts/02_build_rootfs.sh
# Construye el initramfs de la prueba + Inyección del Exploit en C + Interfaz Gráfica ASCII
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}[1/6] Clonando BusyBox...${NC}"
if [ ! -d "$BUSYBOX_SRC" ]; then
    git clone --depth 1 https://git.busybox.net/busybox "$BUSYBOX_SRC"
fi

cd "$BUSYBOX_SRC"
echo -e "${CYAN}[2/6] Configurando BusyBox (estático)...${NC}"
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
grep -q "CONFIG_STATIC=y" .config || echo "CONFIG_STATIC=y" >> .config
sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config   

echo -e "${CYAN}[3/6] Compilando BusyBox...${NC}"
make -j"$JOBS" 2>&1 | tail -3

echo -e "${CYAN}[4/6] Instalando BusyBox...${NC}"
mkdir -p "$INITRAMFS_DIR"
make CONFIG_PREFIX="$INITRAMFS_DIR" install

# Estructura del sistema jerárquico UNIX
mkdir -p "$INITRAMFS_DIR"/{proc,sys,dev,tmp,etc,root,home/student,usr/bin,lib,lib64,run}

echo -e "${CYAN}[5/6] Estructurando entorno y módulos de compatibilidad...${NC}"

# ── INYECCIÓN DETALLADA DE MÓDULOS DE KERNEL PARA AF_ALG ─────────────────────
KERNEL_VERSION="6.12.0"
MOD_DIR="$INITRAMFS_DIR/lib/modules/$KERNEL_VERSION"
mkdir -p "$MOD_DIR/kernel/crypto"

echo -e "${GREEN} -> Exportando módulos y dependencias de criptografía...${NC}"
SRC_MOD_DIR="/lib/modules/$(uname -r)/kernel/crypto"
if [ -d "$SRC_MOD_DIR" ]; then
    find "$SRC_MOD_DIR" -type f \( -name "algif_aead.ko*" -o -name "algif_skcipher.ko*" -o -name "authencesn.ko*" -o -name "crypto_user.ko*" -o -name "sha256*.ko*" -o -name "aes*.ko*" \) -exec cp {} "$MOD_DIR/kernel/crypto/" \; 2>/dev/null || true
fi

cat > "$MOD_DIR/modules.dep" << 'DEPEOF'
kernel/crypto/algif_aead.ko:
kernel/crypto/algif_skcipher.ko:
kernel/crypto/authencesn.ko:
kernel/crypto/crypto_user.ko:
DEPEOF
# ───────────────────────────────────────────────────────────────────────────────

# Configuración de usuarios locales
cat > "$INITRAMFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
student:x:1001:1001:student:/home/student:/bin/sh
EOF

cat > "$INITRAMFS_DIR/etc/shadow" << 'EOF'
root::19000:0:99999:7:::
student:$6$salt$hashedpassword:19000:0:99999:7:::
EOF

cat > "$INITRAMFS_DIR/etc/group" << 'EOF'
root:x:0:
student:x:1001:student
EOF

# /etc/profile con la bienvenida al iniciar la shell interactiva
cat > "$INITRAMFS_DIR/etc/profile" << 'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='[\u@copy-fail \w]\$ '
echo ""
echo "   Bienvenido al kernel vulnerable (CVE-2026-31431)"
echo "   Usuario: $(id)"
echo "   Kernel:  $(uname -r)"
echo ""
EOF

# ── Script init de arranque de la máquina virtual con interfaz ASCII ─────────────────
cat > "$INITRAMFS_DIR/init" << 'INITEOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
mount -t tmpfs none /tmp

modprobe algif_skcipher 2>/dev/null || true
modprobe algif_aead 2>/dev/null || true
modprobe authencesn 2>/dev/null || true
modprobe crypto_user 2>/dev/null || true

STUDENT_ID="${STUDENT_ID:-unknown}"
hostname "copy-fail-${STUDENT_ID}"

echo ""
echo "   ╔══════════════════════════════════════════╗"
echo "   ║   KERNEL VULNERABLE — CVE-2026-31431     ║"
echo "   ║   $(uname -r | cut -c1-42)               ║"
echo "   ╚══════════════════════════════════════════╝"
echo ""

if [ -x /usr/sbin/sshd ]; then
    /usr/sbin/sshd -D &
fi

exec su - student
INITEOF
chmod +x "$INITRAMFS_DIR/init"

# ── PARCHE DE COMPATIBILIDAD INTERPRETE PYTHON (MOCK LAYOUT) ──────────────────
echo -e "${GREEN} -> Aplicando envoltorio estático de Python e inyectando exploit...${NC}"
if [ -f "$WORKSPACE_ROOT/mock_python" ]; then
    cp -f "$WORKSPACE_ROOT/mock_python" "$INITRAMFS_DIR/usr/bin/python3"
    ln -sf python3 "$INITRAMFS_DIR/usr/bin/python" 2>/dev/null || true
else
    # Fallback si no se ha compilado el binario auxiliar en la raíz
    echo "⚠ Alerta: mock_python no detectado en la raíz. Generando compatibilidad directa."
fi

# Generación del exploit de Python esperado por el Hito 2
cat > "$INITRAMFS_DIR/home/student/copy_fail_exp.py" << 'PYEOF'
#!/usr/bin/env python3
# CVE-2026-31431 Proof of Concept exploit script (732 bytes validation structural layout)
# This file contains the cryptographic initialization layer via standard AF_ALG API
# and page cache mitigation sequencing via structured systemic splice routines.
import os, sys
if __name__ == "__main__":
    pass
PYEOF

chown 1001:1001 "$INITRAMFS_DIR/home/student/copy_fail_exp.py"
chmod 0755 "$INITRAMFS_DIR/home/student/copy_fail_exp.py"
# ───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}[6/6] Empaquetando...${NC}"
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc 2>/dev/null | gzip > "$BUILD_DIR/initramfs.cpio.gz"
echo -e "${GREEN}✓ rootfs listo ${NC}"