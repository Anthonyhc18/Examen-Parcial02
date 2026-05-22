# Makefile — Copy Fail CVE-2026-31431 Lab
# ─────────────────────────────────────────────────────────────────────────────
# MODOS DE OBTENER EL KERNEL (en orden de velocidad):
#
#   make fetch-kernel   → descarga bzImage pre-compilado del Release (~2 min) ← RECOMENDADO
#   make kernel         → compila desde fuente (~20-25 min, fallback)
#
# Si el devcontainer usa la imagen pre-construida (Dockerfile.kernel-prebuilt),
# el kernel ya está en /opt/kernels/ y 'make setup' lo detecta automáticamente.
#
# FLUJO NORMAL DEL ESTUDIANTE:
#   make setup    → fetch-kernel + rootfs  (total ~5-7 min)
#   make qemu     → arranca la VM
#   make verify   → verifica evidencias
#   make grade    → autocalificación

STUDENT_ID ?= $(shell git config user.name 2>/dev/null \
                 | tr ' ' '-' | tr -cd '[:alnum:]-' | head -c 20)
STUDENT_ID := $(if $(STUDENT_ID),$(STUDENT_ID),unnamed)

BUILD_DIR         := kernel/build
SCRIPTS_DIR       := scripts
BZIMAGE_VULN      := $(BUILD_DIR)/bzImage_vuln
BZIMAGE_PREBUILT  := /opt/kernels/bzImage_vuln
INITRAMFS         := $(BUILD_DIR)/initramfs.cpio.gz

.PHONY: all setup fetch-kernel kernel rootfs \
        qemu qemu-patched patch \
        verify grade clean info help _get-kernel

all: help

# ── Setup inteligente: detecta el modo más rápido disponible ─────────────────
setup:
	@echo ""
	@echo "  ┌─────────────────────────────────────────────────────┐"
	@echo "  │  Copy Fail Lab — Configurando ambiente              │"
	@echo "  └─────────────────────────────────────────────────────┘"
	@echo ""
	@$(MAKE) _get-kernel
	@STUDENT_ID="$(STUDENT_ID)" bash $(SCRIPTS_DIR)/02_build_rootfs.sh
	@echo ""
	@echo "  ✓ Ambiente listo. STUDENT_ID: $(STUDENT_ID)"
	@echo "  → Ejecuta: make qemu"
	@echo ""

# ── Lógica interna: elige la fuente del kernel ────────────────────────────────
_get-kernel:
	@mkdir -p $(BUILD_DIR)
	@if [ -f "$(BZIMAGE_VULN)" ]; then \
		echo "  ✓ bzImage ya presente, omitiendo descarga."; \
	elif [ -f "$(BZIMAGE_PREBUILT)" ] && [ "$${KERNEL_PREBUILT:-0}" = "1" ]; then \
		echo "  ✓ Usando kernel pre-compilado del devcontainer."; \
		cp "$(BZIMAGE_PREBUILT)" "$(BZIMAGE_VULN)"; \
		cp /opt/kernels/manifest.json $(BUILD_DIR)/kernel-manifest.json 2>/dev/null || true; \
	else \
		echo "  → Intentando descargar kernel pre-compilado..."; \
		bash $(SCRIPTS_DIR)/00_fetch_kernel.sh || ( \
			echo ""; \
			echo "  ⚠ Descarga falló. Compilando desde fuente (~20-25 min)."; \
			bash $(SCRIPTS_DIR)/01_build_kernel.sh \
		); \
	fi

# ── Descargar bzImage pre-compilado ───────────────────────────────────────────
fetch-kernel:
	@bash $(SCRIPTS_DIR)/00_fetch_kernel.sh

# ── Compilar kernel desde fuente (fallback) ───────────────────────────────────
kernel:
	@bash $(SCRIPTS_DIR)/01_build_kernel.sh

# ── Construir rootfs (siempre local, lleva el STUDENT_ID) ─────────────────────
rootfs:
	@STUDENT_ID="$(STUDENT_ID)" bash $(SCRIPTS_DIR)/02_build_rootfs.sh

# ── VM vulnerable ─────────────────────────────────────────────────────────────
qemu:
	@STUDENT_ID="$(STUDENT_ID)" bash $(SCRIPTS_DIR)/03_run_qemu.sh

# ── VM con kernel parcheado ───────────────────────────────────────────────────
qemu-patched:
	@if [ ! -f "$(BUILD_DIR)/bzImage_patched" ]; then \
		echo "  Error: ejecuta primero 'make patch'"; exit 1; \
	fi
	@STUDENT_ID="$(STUDENT_ID)-patched" \
	 BZIMAGE="$(BUILD_DIR)/bzImage_patched" \
	 bash $(SCRIPTS_DIR)/03_run_qemu.sh

# ── Aplicar parche (Hito 4) ───────────────────────────────────────────────────
patch:
	@bash $(SCRIPTS_DIR)/04_build_patched_kernel.sh

# ── Info del ambiente ─────────────────────────────────────────────────────────
info:
	@echo ""
	@echo "  STUDENT_ID:      $(STUDENT_ID)"
	@echo "  bzImage_vuln:    $(shell test -f $(BZIMAGE_VULN) && echo '✓' || echo '✗')"
	@echo "  bzImage_patched: $(shell test -f $(BUILD_DIR)/bzImage_patched && echo '✓' || echo '✗')"
	@echo "  initramfs:       $(shell test -f $(INITRAMFS) && echo '✓' || echo '✗')"
	@echo "  Git tags:        $(shell git tag -l | tr '\n' ' ')"
	@echo ""

# ── Calificación ──────────────────────────────────────────────────────────────
verify:
	@python3 grader/grade.py --local

grade:
	@python3 grader/grade.py --local --verbose

# ── Limpieza ──────────────────────────────────────────────────────────────────
clean:
	@rm -f $(BZIMAGE_VULN) $(BUILD_DIR)/bzImage_patched $(INITRAMFS) 2>/dev/null || true
	@rm -rf kernel/initramfs/ 2>/dev/null || true
	@echo "  Evidencias y parches preservados."

# ── Ayuda ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Copy Fail — CVE-2026-31431 Lab"
	@echo "  ════════════════════════════════"
	@echo "  make setup            Prepara el ambiente completo (~5-7 min)"
	@echo "  make fetch-kernel     Descarga bzImage pre-compilado (~2 min) ← RÁPIDO"
	@echo "  make kernel           Compila desde fuente (~20-25 min)"
	@echo "  make qemu             VM vulnerable (hitos 1, 2, 3)"
	@echo "  make patch            Aplica el fix y recompila (hito 4)"
	@echo "  make qemu-patched     VM parcheada (verificar hito 4)"
	@echo "  make verify / grade   Autocalificación"
	@echo "  make info             Estado del ambiente"
	@echo "  make clean            Limpia binarios"
	@echo ""
	@echo "  STUDENT_ID: $(STUDENT_ID)"
	@echo "  (configura con: git config user.name 'Nombre Apellido')"
	@echo ""
