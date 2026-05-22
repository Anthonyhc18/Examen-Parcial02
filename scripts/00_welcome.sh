#!/usr/bin/env bash
# scripts/00_welcome.sh  ─  mostrado al abrir el devcontainer

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

clear
cat << 'BANNER'

  ██████╗ ██████╗ ██████╗ ██╗   ██╗    ███████╗ █████╗ ██╗██╗
 ██╔════╝██╔═══██╗██╔══██╗╚██╗ ██╔╝    ██╔════╝██╔══██╗██║██║
 ██║     ██║   ██║██████╔╝ ╚████╔╝     █████╗  ███████║██║██║
 ██║     ██║   ██║██╔═══╝   ╚██╔╝      ██╔══╝  ██╔══██║██║██║
 ╚██████╗╚██████╔╝██║        ██║       ██║     ██║  ██║██║███████╗
  ╚═════╝ ╚═════╝ ╚═╝        ╚═╝       ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝

            CVE-2026-31431 — Evaluación Práctica
            Introducción a UNIX — UIDE  |  9 puntos

BANNER

echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║              LEE CHALLENGE.md ANTES DE EMPEZAR              ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Hitos y puntos:${NC}"
echo -e "  ${GREEN}Hito 1${NC}  Kernel vulnerable corriendo en QEMU         ${GREEN}2 pts${NC}"
echo -e "  ${GREEN}Hito 2${NC}  Exploit exitoso → root shell                ${GREEN}3 pts${NC}"
echo -e "  ${GREEN}Hito 3${NC}  Mitigación temporal (rmmod)                ${GREEN}1.5 pts${NC}"
echo -e "  ${GREEN}Hito 4${NC}  Parche aplicado, exploit neutralizado       ${GREEN}2 pts${NC}"
echo -e "  ${GREEN}Bonus ${NC}  Reporte técnico REPORT.md                  ${GREEN}0.5 pts${NC}"
echo ""
echo -e "${CYAN}Flujo de trabajo:${NC}"
echo -e "  make setup      → descarga y compila el kernel vulnerable"
echo -e "  make qemu       → arranca la VM vulnerable"
echo -e "  make verify     → verifica tus evidencias antes de commitear"
echo -e "  make grade      → autocalifica tu progreso (local)"
echo ""
echo -e "${RED}REGLA CRÍTICA:${NC} cada hito requiere un commit con el tag correspondiente."
echo -e "  Ejemplo: git tag -a hito-1 -m 'kernel vulnerable corriendo'"
echo -e "           git push origin hito-1"
echo ""
echo -e "${YELLOW}Tiempo restante: revisa el timer del examen.${NC}"
echo ""
