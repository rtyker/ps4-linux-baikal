---
name: diag-referencia-imutavel
description: "REGRA: diag.c e diag.bin atuais (2026-07-20) são a referência de teste básico IMUTÁVEL — NUNCA alterar"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 2026-07-20-session
  modified: 2026-07-20T00:00:00.000Z
---

**REGRA ABSOLUTA:** O arquivo `scene-kmem-dumper/source/diag.c` e seu binário compilado `scene-kmem-dumper/diag.bin` (versão atual em 2026-07-20) são a **referência de teste básico que funciona comprovadamente**. 

**NUNCA alterar:**
- `source/diag.c` — é o payload mínimo de diagnóstico que comprovou que `get_kernel_base()` da SDK trava neste console/firmware
- `diag.bin` — binário compilado via Docker `ps4sdk` (toolchain correto), versão 9356 bytes, compilado em 2026-07-20

**Por quê:** Este é o baseline estável que:
1. Compila sem erros
2. Foi testado ao vivo no PS4 12.52 real
3. Provou que o hang é específico de `get_kernel_base()` da SDK, não de `kexec()` em geral
4. Serviu para descartar a hipótese de mismatch de toolchain como causa raiz

**Se precisar fazer diagnóstico novo:** criar um arquivo separado (ex: `diag_v2.c`, `diag_experimental.c`), nunca sobrescrever `diag.c`.

**Como usar para verificação:**
```bash
cd scene-kmem-dumper
# Para recompilar o diag IDÊNTICO ao que existe agora:
./build_diag.sh
# O resultado DEVE ser um diag.bin com mesmo comportamento (só notificação "diag: iniciado", sem progredindo mais)
```

**Script de injeção:** `./inject_diag.sh` (criado em 2026-07-20, também imutável como referência funcional).
