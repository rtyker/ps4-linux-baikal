---
name: sessao-2026-07-20-kern-base-finder
description: "Sessão 2026-07-20: desenvolvimento do kern_base_finder.c — método dinâmico para achar kernel_base via LSTAR (MSR 0xC0000082) + fallback scan ELF com copyout fault-safe, testado ao vivo no PS4 12.52"
metadata:
  node_type: memory
  type: project
  originSessionId: 2026-07-20-session
  modified: 2026-07-20T12:45:00.000Z
---

## Objetivo
Dumper kernel 12.52 sem depender de `get_kernel_base()` SDK (offsets K1252_* que travam), usando método dinâmico em Ring 0 via `kexec`: ler `IA32_LSTAR` (MSR 0xC0000082) → `LSTAR - 0x1C0` → validar; se falhar, scan ELF backward 2MB com `copyout` fault-safe.

## Arquivos criados/modificados
- `scene-kmem-dumper/source/kern_base_finder.c` — rotina Ring 0 chamada via `kexec`
- `scene-kmem-dumper/source/kern_dumper_main.c` — novo `_main` TCP 9020
- `scene-kmem-dumper/Makefile` — compila apenas `kern_dumper_main.c` + `kern_base_finder.c`

## Correções críticas aplicadas (BUGs descobertos e fixados)

### BUG #1 — Chamada userland de rotina Ring 0 (CORRIGIDO)
- `kern_dumper_main.c` chamava `kern_base_finder(td, &kbr)` direto → `rdmsr` em userland = #GP/KP imediato
- **Fix:** `kexec((void *)&kern_base_finder, &kbr)` — padrão dos `kpayload_*` em `payload_utils.c`

### BUG #2 — Dereference bruto de ponteiro kernel sem copyout (CORRIGIDO no fallback)
- Loop de scan fazia `uint32_t *p = (uint32_t *)addr; if (*p == 0x464c457f)` — acesso direto a memória kernel
- Se página não mapeada → page fault fatal em Ring 0 = Kernel Panic total (confirmado: travou console 1x)
- **Fix no fallback scan:** usar `copyout_kernel()` wrapper que chama `build_kpayload(1252, copyout_macro)` → obtém `copyout` fault-safe → leitura retorna erro em vez de panic

### BUG #3 — `rdmsr` com constraint `=A` errado em x86-64 (CORRIGIDO)
- `=A` captura só RAX OU RDX (escolha do compilador), não o par EDX:EAX combinado
- **Fix:** dois registradores separados: `__asm__ volatile("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr))`

### BUG #4 — `build_kpayload` espera variável `uint8_t *kernel_base` (CORRIGIDO)
- Macro `copyout_macro` expande atribuição para `kernel_base` (ponteiro), não `uint64_t`
- Wrapper `copyout_kernel()` declara `uint8_t *kernel_base` antes do `build_kpayload`

## Implementação atual (kern_base_finder.c)
1. **Método LSTAR (rápido):** `rdmsr(0xC0000082)` → valida ≥ `0xFFFF000000000000` → `base = lstar - 0x1C0` → valida base canônica → retorna
2. **Fallback Scan ELF (robusto):** se LSTAR falhar, começa em `lstar_alinhado_2MB` (ou `0xFFFFFFFF80000000` default) → scan 256 páginas 2MB pra trás → cada página: `copyout_kernel(addr, &magic, 4)` → se `magic == 0x464c457f`: copia ELF header → itera Program Headers via `copyout_kernel` → calcula `min_vaddr`/`max_vaddr` dos `PT_LOAD` → `kernel_base = scan_addr - min_vaddr`, `kernel_size = max_vaddr - min_vaddr`
3. Ambos métodos usam `copyout` fault-safe (páginas não mapeadas → erro, não panic)

## Testes ao vivo 2026-07-20

### Teste 1 — método LSTAR apenas (versão anterior)
- Resultado: `LSTAR=0x0 base=0x0 size=0x0` → `rdmsr` retorna 0 no contexto `kexec`
- Payload abre porta 9020 mas dumper envia 0 bytes (base 0)

### Teste 2 — fallback scan com copyout (versão com debug, recompilada Docker ps4sdk)
- **Testado ao vivo 2026-07-20:** injetado via `inject.sh`
- **TV mostrou:**
  ```
  kern-dumper: iniciado
  kern-dumper: achando kernel base via kexec...
  kern-dumper: LSTAR=0x0 base=0x0 size=0x0
  kern-dumper: escutando na porta 9020
  kern-dumper: enviando 0x2034af0 bytes de +0x0
  ```
- **Análise:** LSTAR=0 (rdmsr falha), scan ELF **não achou** o magic `\x7fELF` — `method_used` não impresso mas base=0 indica que ambos métodos falharam
- **Receiver:** conectou na 9020, pediu dump, timeout (0 bytes salvos) — payload enviava zeros por base=0

### Teste 3 — versão com debug de scan (recompilada Docker ps4sdk, aguardando power cycle)
- Novos campos de debug em `kern_base_result_t`: `scan_addr_found`, `magic_found`, `phnum_found`, `min_vaddr_found`, `max_vaddr_found`
- **Próximo teste:** aguardando power cycle completo

## Scripts de apoio criados
- `scene-kmem-dumper/rebuild.sh` — recompila via Docker `ps4sdk`, target padrão (`app.bin`, o dumper completo TCP 9020)
- `scene-kmem-dumper/inject.sh` — roda `send_payload_loop.py` apontando pro `app.bin`
- `scene-kmem-dumper/build_diag.sh` (criado 2026-07-20) — compila via Docker `ps4sdk` só o target `diag.bin` do Makefile (payload mínimo `source/diag.c`: `initKernel()`+`initLibc()`+notificação+`get_kernel_base()`+notificação, sem TCP/socket). Já testado: build limpo, gerou `diag.bin` (9356 bytes). Objetivo: isolar se `get_kernel_base()`/`kexec()` trava ou não, sem a complexidade do dumper TCP completo junto.
- `scene-kmem-dumper/inject_diag.sh` (criado 2026-07-20) — análogo ao `inject.sh`, mas roda `send_payload_loop.py` apontando pro `diag.bin` em vez do `app.bin`.

### Teste ao vivo `diag.bin` — 2026-07-20 (RESULTADO IMPORTANTE)
- Injetado via `inject_diag.sh` (build feito com a toolchain Docker `ps4sdk` correta, não gcc do host).
- TV mostrou só: `"diag: iniciado"` — nunca apareceu `"diag: kernel_base = 0x..."` nem `"diag: get_kernel_base FALHOU (-1)"`.
- **Console NÃO travou** (confirmado pelo usuário): continuou respondendo normalmente, sem Kernel Panic/reboot/tela preta.
- **Descarta a hipótese de mismatch de toolchain** (era a suspeita aberta ao pausar a sessão 2026-07-19) — mesmo payload mínimo, mesma toolchain oficial, mesmo comportamento de travar sem progredir.
- **CORREÇÃO (apontada pelo usuário):** `app.bin` (o dumper atual, `kern_dumper_main.c`+`kern_base_finder.c`) **NÃO usa `get_kernel_base()` da SDK** — usa o método próprio via LSTAR/MSR + `kexec()` (ver seção "Implementação atual" acima). Esse método NÃO trava: no Teste 2 acima, o `kexec()` retornou normalmente (`LSTAR=0x0 base=0x0 size=0x0`, seguiu até abrir a porta 9020). Quem trava é só a função `get_kernel_base()` da SDK original, usada apenas em `diag.c`.
- **Conclusão final corrigida:** o hang é específico de `get_kernel_base()` da SDK (offsets `K1252_*`), não de `kexec()` em geral. O `kern_base_finder.c` customizado (usado no `app.bin` real) não trava — só retorna valores zerados até agora (LSTAR=0, magic ELF não encontrado). São dois problemas diferentes: `diag.bin`/SDK trava; `app.bin`/`kern_base_finder.c` retorna mas com dado errado.
- **Consequência prática:** `diag.bin` já cumpriu seu papel (descartou toolchain como causa) e não precisa de mais testes agora. A investigação ativa volta a ser 100% sobre por que `LSTAR` lê 0 e o scan ELF não acha o magic dentro de `kern_base_finder.c` — não há mais motivo pra investigar `get_kernel_base()` da SDK, já que o dumper atual não depende dela.

## Próximo passo exato
1. Power cycle completo (tirar da tomada 15–30s)
2. PS4: GoldHEN → Payload Server (9090) tela aberta
3. PC term1: `python3 receive_kmem_dump.py`
4. PC term2: `./inject.sh`
5. TV: observar `LSTAR=0x... base=0x... size=0x...` → se sucesso, receiver conecta e salva `kmem_dump_*.bin`

## Lições registradas
- **NUNCA** chamar rotina com `rdmsr` direto do userland — sempre via `kexec`
- **NUNCA** dereference ponteiro kernel direto — sempre via `copyout`/`copyin` fault-safe
- `build_kpayload(1252, copyout_macro)` funciona e retorna `copyout` válido em Ring 0
- LSTAR pode retornar 0 no contexto `kexec` (registradores não preservados?) → fallback scan é obrigatório
- Validar endereços canônicos (`≥ 0xFFFF000000000000`) antes de usar
- **`app.bin` só permite UM teste por power cycle** — ver memória dedicada [[app-bin-um-teste-por-powercycle]]. Reinjetar sem reiniciar o PS4 entre tentativas não progride; todo ciclo de teste ao vivo precisa contar o tempo de power cycle completo como parte do custo de cada iteração.