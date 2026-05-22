#!/usr/bin/env python3
"""
grader/grade.py
Autocalificador de Copy Fail CVE-2026-31431 Lab
Uso:
    python3 grader/grade.py --local [--verbose]
    python3 grader/grade.py --repo https://github.com/student/repo (modo CI)
"""
import os
import re
import sys
import json
import subprocess
import argparse
from pathlib import Path
from datetime import datetime, timezone

# ── Rutas ──────────────────────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).parent.parent
EVIDENCE_DIR = REPO_ROOT / "evidence"
PATCHES_DIR = REPO_ROOT / "patches"

# ── Rubric ─────────────────────────────────────────────────────────────────────
RUBRIC = {
    "hito-1": {
        "nombre": "Kernel vulnerable confirmado",
        "puntos": 2.0,
        "tag": "hito-1",
        "archivo": "hito1_vuln_confirmed.txt",
        "checks": [
            ("kernel_version", r"6\.\d+", "Versión de kernel Linux 6.x presente"),
            ("user_is_student", r"uid=\d+\([a-zA-Z0-9_-]+\)", "Identidad de usuario presente"),
            ("not_root_before", r"uid=(?!0)", "Usuario NO es root antes del exploit"),
            ("hostname_present", r"copy-fail-[a-zA-Z0-9-]+", "Hostname de la VM presente"),
            ("algif_module", r"algif|AF_ALG|CRYPTO_USER_API_AEAD", "Módulo AF_ALG/algif mencionado"),
        ]
    },
    "hito-2": {
        "nombre": "Exploit exitoso → root shell",
        "puntos": 3.0,
        "tag": "hito-2",
        "archivo": "hito2_root_shell.txt",
        "checks": [
            ("root_uid", r"uid=0\(root\)", "UID 0 (root) presente en la evidencia"),
            ("hostname_match", r"copy-fail-", "Hostname de la VM coincide"),
            ("not_empty", r".{50,}", "Archivo tiene contenido suficiente (>50 chars)"),
            ("date_present", r"20\d{2}-\d{2}-\d{2}|\w+ \w+ \d+ \d+:\d+:\d+ UTC \d{4}", "Timestamp presente"),
        ]
    },
    "hito-3": {
        "nombre": "Mitigación temporal (rmmod algif_aead)",
        "puntos": 1.5,
        "tag": "hito-3",
        "archivo": "hito3_mitigation.txt",
        "checks": [
            ("module_removed", r"módulo NO cargado|no loaded|not found|mitigaci", "Módulo removido documentado"),
            ("exploit_failed", r"fall|error|Error|fail|FAIL|Permission denied|EBADMSG", "Exploit falló post-mitigación"),
            ("hostname_present", r"copy-fail-", "Hostname de la VM presente"),
        ]
    },
    "hito-4": {
        "nombre": "Parche permanente aplicado",
        "puntos": 2.0,
        "tag": "hito-4",
        "archivo": "hito4_patched.txt",
        "patch_file": "fix_algif_aead.patch",
        "checks": [
            ("kernel_mentioned", r"6\.\d+", "Versión de kernel presente"),
            ("exploit_failed", r"fall|error|Error|fail|FAIL|Permission denied|EBADMSG|Operaci", "Exploit falló en kernel parcheado"),
            ("student_id", r"uid=\d+\([a-zA-Z0-9_-]+\)", "Identidad de usuario presente"),
        ],
        "patch_checks": [
            ("modifies_algif_aead", r"algif_aead\.c", "Parche toca algif_aead.c"),
            ("out_of_place", r"tsgl|tx_sgl|txsg|req->src.*tsg|tsg.*src", "Parche usa TX SGL separado"),
        ]
    },
    "bonus": {
        "nombre": "Reporte técnico",
        "puntos": 0.5,
        "tag": "bonus",
        "archivo_repo": "REPORT.md",
        "checks": [
            ("min_length", r"[\s\S]{300,}", "Reporte tiene mínimo 300 caracteres"),
            ("algif_mentioned", r"algif|authencesn|scatterlist|sg_chain|page.cache", "Términos técnicos del CVE presentes"),
            ("setuid_mentioned", r"setuid|suid|su\b", "Conexión con conceptos del curso (setuid)"),
        ]
    }
}

# ══════════════════════════════════════════════════════════════════════════════


def git_tags() -> list[str]:
    """Obtiene los tags git del repositorio local."""
    try:
        result = subprocess.run(
            ["git", "tag", "-l"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip().split("\n") if result.returncode == 0 else []
    except Exception:
        return []


def git_log_for_tag(tag: str) -> dict | None:
    """Obtiene info del commit asociado a un tag."""
    try:
        result = subprocess.run(
            ["git", "log", "-1", "--format=%H|%aI|%s", tag],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split("|", 2)
            return {"hash": parts[0][:8], "date": parts[1], "msg": parts[2]}
    except Exception:
        pass
    return None


def check_evidence_file(filepath: Path, checks: list) -> tuple[int, list]:
    """Ejecuta las verificaciones sobre un archivo de evidencia."""
    if not filepath.exists():
        return 0, [("❌", "Archivo no encontrado", f"Falta: {filepath.name}")]

    content = filepath.read_text(encoding="utf-8", errors="replace")
    passed = 0
    results = []

    for check_id, pattern, description in checks:
        if re.search(pattern, content, re.IGNORECASE):
            results.append(("✅", description, "OK"))
            passed += 1
        else:
            results.append(("⚠️ ", description, f"No encontrado (patrón: {pattern})"))

    return passed, results


def unique_hostname_check(hito1_file: Path, hito2_file: Path) -> bool:
    """Anti-copia: verifica que los hostnames coinciden entre hitos del mismo estudiante."""
    if not hito1_file.exists() or not hito2_file.exists():
        return True  # no penalizar si falta alguno

    h1 = hito1_file.read_text(errors="replace")
    h2 = hito2_file.read_text(errors="replace")

    # Extrae hostnames
    hn1 = re.findall(r"copy-fail-([a-zA-Z0-9-]+)", h1)
    hn2 = re.findall(r"copy-fail-([a-zA-Z0-9-]+)", h2)

    if not hn1 or not hn2:
        return True  # si no hay hostname no podemos comparar

    return hn1[0] == hn2[0]


def grade_local(verbose: bool = False) -> dict:
    """Califica el repositorio local."""

    tags = git_tags()
    total = 0.0
    max_total = sum(h["puntos"] for h in RUBRIC.values())
    results = {}

    print("\n" + "═" * 60)
    print("  AUTOCALIFICADOR — Copy Fail CVE-2026-31431")
    print("═" * 60 + "\n")

    # Obtener student ID del git config
    try:
        r = subprocess.run(["git", "config", "user.name"], capture_output=True,
                          text=True, cwd=REPO_ROOT, timeout=5)
        student_name = r.stdout.strip() or "desconocido"
    except Exception:
        student_name = "desconocido"

    print(f"  Estudiante: {student_name}")
    print(f"  Repositorio: {REPO_ROOT}")
    print(f"  Fecha evaluación: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print()

    for hito_id, hito in RUBRIC.items():
        nombre = hito["nombre"]
        pts_max = hito["puntos"]
        tag = hito["tag"]
        has_tag = tag in tags

        print(f"─── {hito_id.upper()} — {nombre} ({pts_max} pts) ───")

        # ¿Tiene el tag?
        if has_tag:
            tag_info = git_log_for_tag(tag)
            if tag_info:
                print(f"  ✅ Tag '{tag}' presente  [{tag_info['hash']}  {tag_info['date'][:10]}]")
            else:
                print(f"  ✅ Tag '{tag}' presente")
        else:
            print(f"  ❌ Tag '{tag}' NO encontrado")

        # Archivo de evidencia
        archivo = hito.get("archivo")
        evidence_path = EVIDENCE_DIR / archivo if archivo else None
        repo_file = hito.get("archivo_repo")
        if repo_file:
            evidence_path = REPO_ROOT / repo_file

        checks = hito.get("checks", [])
        passed = 0
        check_results = []

        if evidence_path:
            passed, check_results = check_evidence_file(evidence_path, checks)
        elif checks:
            passed, check_results = 0, [("❌", "Sin archivo de evidencia", "")]

        # Verificación del parche (Hito 4)
        patch_passed = 0
        patch_total = 0
        if hito_id == "hito-4":
            patch_file = PATCHES_DIR / hito.get("patch_file", "fix_algif_aead.patch")
            patch_checks = hito.get("patch_checks", [])
            patch_total = len(patch_checks)
            if patch_file.exists():
                p_passed, p_results = check_evidence_file(patch_file, patch_checks)
                patch_passed = p_passed
                if verbose:
                    print(f"  Parche ({patch_file.name}):")
                    for icon, desc, note in p_results:
                        print(f"    {icon} {desc}")
            else:
                print(f"  ❌ Parche no encontrado: {patch_file.name}")

        if verbose and check_results:
            for icon, desc, note in check_results:
                print(f"  {icon} {desc}")

        # Calcular puntos del hito
        total_checks = len(checks) + patch_total
        all_passed = passed + patch_passed
        tag_bonus = 1 if has_tag else 0

        if total_checks > 0:
            # 60% por la evidencia (proporcional), 40% por el tag
            pts_evidence = pts_max * 0.60 * (all_passed / total_checks)
            pts_tag = pts_max * 0.40 * tag_bonus
            pts_hito = round(pts_evidence + pts_tag, 2)
        else:
            pts_hito = pts_max if has_tag else 0.0

        # Anti-copia: si los hostnames no coinciden, penalizar hito-2
        if hito_id == "hito-2":
            h1_path = EVIDENCE_DIR / "hito1_vuln_confirmed.txt"
            h2_path = EVIDENCE_DIR / "hito2_root_shell.txt"
            if not unique_hostname_check(h1_path, h2_path):
                print(f"  ⚠️  ADVERTENCIA: Hostname no coincide entre hito-1 y hito-2")
                pts_hito *= 0.5  # penalización del 50%

        total += pts_hito
        results[hito_id] = {
            "pts": pts_hito,
            "max": pts_max,
            "tag": has_tag,
            "checks_passed": all_passed,
            "checks_total": total_checks
        }

        pts_str = f"{pts_hito:.1f}/{pts_max:.1f}"
        status = "✅" if pts_hito >= pts_max * 0.7 else ("⚠️ " if pts_hito > 0 else "❌")
        print(f"  {status} Puntos: {pts_str}  ({all_passed}/{total_checks} checks)")
        print()

    # ── Resumen ────────────────────────────────────────────────────────────────
    print("═" * 60)
    total = round(total, 2)
    pct = (total / max_total) * 100
    print(f"\n  TOTAL: {total:.2f} / {max_total:.1f} puntos  ({pct:.0f}%)\n")

    if pct >= 90:
        print("  ⭐ Excelente trabajo — dominaste el CVE completo.")
    elif pct >= 70:
        print("  ✅ Buen trabajo — completaste los hitos principales.")
    elif pct >= 50:
        print("  ⚠️  Trabajo parcial — algunos hitos quedan por completar.")
    else:
        print("  ❌ Progreso insuficiente — revisa CHALLENGE.md.")

    print()
    print("  Recuerda hacer push de todos tus tags:")
    print("  git push origin main --tags")
    print()

    return {"student": student_name, "total": total, "max": max_total, "hitos": results}


def main():
    parser = argparse.ArgumentParser(description="Autocalificador CVE-2026-31431 Lab")
    parser.add_argument("--local", action="store_true", help="Calificar repositorio local")
    parser.add_argument("--verbose", action="store_true", help="Mostrar detalles de cada check")
    parser.add_argument("--json", action="store_true", help="Salida en JSON (para CI)")
    args = parser.parse_args()

    result = grade_local(verbose=args.verbose)

    if args.json:
        print(json.dumps(result, indent=2))

    sys.exit(0 if result["total"] > 0 else 1)


if __name__ == "__main__":
    main()
