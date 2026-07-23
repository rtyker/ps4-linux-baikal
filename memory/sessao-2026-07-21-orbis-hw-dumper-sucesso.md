# Sessão 2026-07-21: orbis-hw-dumper — Histórico Completo de Erros e Acertos

## Regras operacionais desta sessão
1. **Sempre registrar erros e acertos nas memórias.**
2. **Sempre commitar localmente antes de qualquer nova tentativa** (git dentro de `orbis-hw-dumper/`).

---

## Contexto e Diagnóstico dos Bugs

No firmware **12.52 (GoldHEN)**, o payload `orbis-hw-dumper` apresentava a falha inicial:
`hw-dumper: FALHA kexec base ret=0 st=0 base=0x0`

---

## Erros e Acertos (ordem cronológica)

### ✅ ACERTO 1 — Correção da ABI do `kexec` (struct kexec_sys_args)
- **Problema:** O código passava `&kargs` (stack pointer de userland) para `kexec`. Em Ring 0, o payload desempacotava `args->user_buf` como resultado, escrevendo fora dos limites.
- **Solução:** Definir `struct kexec_sys_args { void *syscall_handler; void *user_buf; }` e passar os ponteiros `fr` e `da` diretamente em `kexec(kpayload_find_base, fr)`.
- **Resultado ao vivo:** `[2] base=0xffffffff96b7c000 copyout=0xffffffff96e395c0` ✅

---

### ❌ ERRO 2 — Offset `0x5f810` para `pmap_mapdev` (errado para FW 12.52)
- **Problema:** O offset apontava para uma função arbitrária, retornando lixo como `va=0xcf9c28af68dcb91c`. `ret=0 status=14 (EFAULT)`.
- **Lição:** Offsets de versões anteriores não se transferem. Sempre validar no dump do kernel da FW alvo.

---

### ❌ ERRO 3 — Offset `0x2C0810` para `pmap_mapdev` (função errada, era `pmap_enter`)
- **Problema:** O offset apontava para `pmap_enter`, que espera `pmap_t *` em `rdi`. Recebendo `0xc2000000`, tentou desreferenciar o ponteiro e causou Kernel Panic / reboot imediato na etapa `[4]`.
- **Lição:** Localizar a função pelo prólogo + referência à string de erro não é suficiente — é preciso validar a assinatura (`rdi=phys_addr` vs `rdi=pmap_t *`).

---

### ❌ ERRO 4 — Offset `0x617E0` para `pmap_mapdev` (causa reboot de cara)
- **Problema:** Chamar `pmap_mapdev` em Ring 0 dentro de `kexec` causa Kernel Panic imediato ("sleeping in invalid context") porque a função tenta adquirir mutexes e colocar a thread em sleep.
- **Confirmado no disassembly:** `0xffffffffdc3b1a53: call 0xffffffffdc6c8300` (vmem lock) antes de qualquer mapeamento.
- **Lição:** NUNCA chamar funções que adquirem mutexes/dormem dentro de `kexec`. Isso reinicia o console de imediato.

---

### ❌ ERRO 5 — Varredura DMAP bruta (`0xffff800000000000 + phys`)
- **Problema:** Tentou ler `volatile uint32_t *` de `0xffff8000c2000000` em Ring 0. DMAP só tem PTEs para RAM física. `0xc2000000` é endereço MMIO PCI — sem PTE → Page Fault em Ring 0 → reboot.
- **Confirmado no disassembly de `pmap_mapdev`:**
  ```asm
  movabs rdx, 0xffff800000000000
  cmp rax, rdi    ; rdi = phys_addr = 0xc2000000
  jbe → ERRO      ; SE phys >= limite_RAM → rejeita
  ```
- **Lição:** DMAP não cobre MMIO PCI. Qualquer acesso de leitura direta a `DMAP_BASE + PCI_PHYS` sem PTE válida causa Triple Fault.

---

### ❌ ERRO 6 — Mapeador de tabelas de páginas via CR3 (`map_physical_2mb`)
- **Problema:** Navegar pelas PTEs via `dmap_base + cr3` em Ring 0. O slot `pml4[511]` retornou um físico não populado no processo de userland, causando Triple Fault imediato no deref de `pdp[510]`.
- **Resultado ao vivo:** Console reiniciou de cara ao injetar o payload.
- **Lição:** Manipular PTEs em Ring 0 sem garantir que todos os ponteiros intermediários estão mapeados no DMAP é fatal.

---

### ✅ ACERTO 2 — Arquitetura fault-safe com `direct_memory_dump` + `copyout`
- **Resultado ao vivo:**
  ```
  [1] kexec achar base ✅
  [2] base=0xffffffff96b7c000 copyout=0xffffffff96e395c0 ✅
  [3] alocando buffer dump ✅
  [4] lendo BAR0 (0xc2000000)...
  [5] BAR0 unpowered/unmapped (zeros)  ← não travou, não reiniciou
  [6] abrindo socket porta 9020 ✅
  [7] aguardando conexao... ✅
  ```
- **Avaliação:** A espinha dorsal TCP (kexec, socket, send) está 100% estável. O problema restante é isolado ao **mapeamento de MMIO físico do BAR0/BAR2 do GbE**.

---

### ❌ ERRO 7 — `sceKernelMapDirectMemory` (EINVAL para endereços MMIO PCI)
- **Resultado ao vivo:**
  ```
  [4] MapDirectMemory ret=-2147352554 va=0       → 0x80020016 = SCE EINVAL
  [4b] pmap_mapdev BAR0 ret=14 va=0x7b6de5172c7d6ef0
  [4c] fallback BAR2 (0xc8800000) ret=-2147352554 va=0
  [4d] pmap_mapdev BAR2 ret=14 va=0x7b6de5172c7d6ef0
  ```
- **Decodificação:**
  - `sceKernelMapDirectMemory` retorna `EINVAL` — a syscall só aceita faixas de memória direta reservadas pelo Orbis OS (não endereços MMIO arbitrários de BAR PCI).
  - `pmap_mapdev ret=14` — o `copyout` bloqueia endereços abaixo de `0xffffffff80000000`.
  - O VA `0x7b6de5172c7d6ef0` é lixo de memória não-inicializada.
- **Arquivo recebido:** `gbe_bar0_dump.bin` = 4096 bytes, 100% zeros. Falso positivo.
- **Lição:** `sceKernelMapDirectMemory` é para RAM direta Orbis, não para MMIO PCI. `pmap_mapdev` em Ring 0 faz `copyout` falhar com EFAULT.

---

### ❌ ERRO 8 — DMAP direto de BAR2 (`0xffff8000c8800000`) em Ring 0
- **Resultado ao vivo:** Console travou na etapa `[4] Ring0 DMAP dump BAR2`.
- **Causa:** Mesma do ERRO 5 — BAR2 (`0xc8800000`) também é MMIO PCI, sem PTE no DMAP → Page Fault em Ring 0.

---

## Diagnóstico Final do GBE no FW 12.52

- O **hardware GBE está completamente desalimentado** no firmware 12.52 em modo de jogo.
- O driver `gbe0` do Orbis **não inicializa a placa de rede** em modo de jogo.
- Não existe um KVA mapeado para o BAR0/BAR2 do GBE no kernel heap do 12.52 (busca exaustiva no `kmem_dump_1252.bin` não encontrou nenhum qword = `0xffff8000c2000000`).
- Para ler registradores de hardware do GbE, precisaria: (a) ativar o GbE via PM antes do dump, ou (b) capturar dump quando o hardware está alimentado (ex: durante acesso de rede ativo do sistema).

---

## Estado dos Commits Locais (git em `orbis-hw-dumper/`)

| Hash | Descrição |
|---|---|
| commit inicial | Baseline `orbis-hw-dumper` |
| `9132150` | test: log retorno sceKernelMapDirectMemory e copyout BAR0/BAR2 |
| `76dafb6` | fix: Ring 0 direct DMAP 32-bit dword dump of BAR2 hardware registers |
| `7a64215` | diag: DMAP não cobre MMIO PCI; pmap_mapdev rejeita phys>=lim_RAM; GBE desalimentado no FW 12.52 |

---

## Resumo das Lições Técnicas

1. **NUNCA** chamar funções que adquirem mutexes/dormem dentro de `kexec` (ex: `pmap_mapdev`, `malloc`, `vmem_alloc`).
2. **DMAP (`0xffff800000000000`)** só tem PTEs para RAM física. Nunca para MMIO PCI.
3. **`copyout` bloqueia** endereços de origem < `0xffffffff80000000`.
4. **`sceKernelMapDirectMemory`** só aceita faixas de RAM direta Orbis, não endereços MMIO PCI.
5. **`pmap_mapdev`** em Ring 0 mapeia via DMAP, mas o VA resultante não pode ser passado ao `copyout`.
6. **GBE (`0xc2000000` / `0xc8800000`)** está desalimentado no FW 12.52 em modo de jogo.
7. A espinha dorsal TCP (kexec + socket + send) está 100% estável e funciona sem Kernel Panic.
