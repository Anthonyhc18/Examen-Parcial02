# Directorio de Parches

## Tu tarea (Hito 4)

Debes crear el archivo `fix_algif_aead.patch` que corrija la vulnerabilidad
CVE-2026-31431 en el kernel Linux.

## ¿Qué debe corregir el parche?

El bug está en `crypto/algif_aead.c`, función `_aead_recvmsg()`.

La raíz del problema (introducida en 2017, commit `72548b093ee3`):
```
req->src = req->dst  ← ambos apuntan al mismo scatterlist
```

Cuando páginas del page cache entran por `splice()`, quedan en el scatterlist
de escritura. La función `crypto_authenc_esn_decrypt()` hace un write fuera de
los límites del área de salida legítima, aterrizando en esas páginas del page cache.

## Cómo crear el parche

### Opción A: Cherry-pick del upstream

```bash
cd kernel/linux

# Requiere historial completo (sin --depth 1)
git remote add upstream https://github.com/torvalds/linux.git
git fetch upstream a664bf3d603d   # el commit del fix
git cherry-pick a664bf3d603d

git diff HEAD~1 HEAD crypto/algif_aead.c > \
  /workspaces/copy-fail-challenge/patches/fix_algif_aead.patch
```

### Opción B: Editar manualmente

Lee el write-up técnico en https://xint.io/blog/copy-fail-linux-distributions
(sección "The Fix") y modifica `crypto/algif_aead.c` para que `req->src`
apunte al TX SGL en lugar del RX SGL.

```bash
cd kernel/linux
# Edita el archivo
vim crypto/algif_aead.c

# Genera el parche
git diff crypto/algif_aead.c > \
  /workspaces/copy-fail-challenge/patches/fix_algif_aead.patch
```

## Verificar que el parche es correcto

```bash
make patch      # aplica el parche y recompila
make qemu-patched  # arranca el kernel parcheado
# Dentro de la VM: python3 copy_fail_exp.py  → debe fallar
```
