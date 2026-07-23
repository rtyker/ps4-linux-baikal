# Backlog do Projeto

Lista de tarefas com prioridade. Itens **em andamento** e investigações ativas ficam nos documentos próprios (`GBE_ACTION_PLAN.md`, `ICC_GBE_TEST_LOG.md`, `RE_KERNEL_GBE_ATTACH.md`); aqui ficam as pendências que não bloqueiam nada agora.

Convenção: `[ ]` pendente · `[~]` em andamento · `[x]` concluído (mover para o histórico do doc correspondente ao concluir).

---

## Prioridade baixa

### [ ] Enxugar o kernel: remover tudo que não é específico do PS4 nem tem uso prático

**Objetivo:** reduzir o `.config` ao que o console realmente usa. Ganhos esperados: builds mais rápidos, menor pico de memória (hoje um build chega a exigir mais RAM do que a máquina tem), `bzImage` menor e menos superfície para bug/regressão.

**Caso exemplar já identificado — `CONFIG_DEBUG_INFO_BTF`:**
- Gera metadados de tipos para **BPF CO-RE** (bpftrace, BCC, libbpf). Nada disso é usado aqui: o debug do projeto é `dmesg` + telnet + leitura de MMIO.
- Custo medido em 2026-07-21: o passo `pahole` consome **10,9 GB de RSS** e roda depois do link, sobre o `vmlinux` pronto. Foi o maior consumidor de memória do build inteiro — maior que o próprio link ThinLTO.
- Desabilitar **não desabilita BPF** (`CONFIG_BPF_SYSCALL` continua funcionando); só remove os metadados.
- O projeto já roda cgroup v1 (`systemd.unified_cgroup_hierarchy=0`), então nem os usos de BPF do systemd pesam.
- Implementação: `scripts/config --disable CONFIG_DEBUG_INFO_BTF` (e provavelmente `CONFIG_DEBUG_INFO_BTF_MODULES`) no `00-build-kernel-7.0.sh`, junto dos outros `scripts/config` que já estão lá.

**Outros candidatos a avaliar** (não verificados ainda — levantar antes de desabilitar):
- Drivers de hardware que o console não tem (o `.config` vem de um defconfig genérico).
- Sistemas de arquivos não usados — hoje só precisamos de ext4 (rootfs), vfat (partição BOOT) e o necessário ao initramfs.
- Subsistemas de virtualização já parcialmente desligados no script (`KVM`, `PARAVIRT`, `HYPERVISOR_GUEST`) — conferir se sobrou algo.
- `CONFIG_DEBUG_INFO` em si: se ninguém for abrir o `vmlinux` em debugger/Ghidra, é muito peso morto. **Cuidado:** hoje ele é útil para inspecionar o binário compilado, então avaliar caso a caso.

**Cuidado ao executar esta tarefa:** mudar o `.config` dispara recompilação ampla (~40 min nesta máquina). Vale agrupar todas as remoções em **uma única** rodada e testar o boot depois, em vez de ir removendo aos poucos. E manter a tag anterior em `boot_referencia/` para rollback — cada teste ao vivo custa um power cycle completo.

---

## Prioridade média

_(vazio)_

## Prioridade alta

### [ ] Confirmar e resolver o S5 incompleto no `poweroff -f` (luz azul não apaga)

**Contexto:** `sync && poweroff -f` já encerra o SO e derruba a rede (ping 100% perda), mas o console fica com a luz azul acesa/pulsando — o desligamento total da fonte (S5) não ocorre.
Achado via Engenharia Reversa do dump Orbis 12.52 em 2026-07-23 (`memory/icc-shutdown-s5-analise-dump-1252.md`): o driver Linux enviava um payload truncado de 6 bytes `{0,0,2,0,1,0}`. O disassembly da rotina nativa `icc_power_shutdown` no offset `0x1d8a3c` do kernel FreeBSD Orbis revelou que a estrutura real possui **32 bytes** (com `cause` no offset `+0x0E`, `depth` no `+0x0F` e `hand` no `+0x10`).

**Status da Execução:**
1. **[X] RE no dump Orbis 12.52:** Concluída via disassembly do offset `0x1d8a3c` no `kmem_dump_1252.bin`. Decodificada a montagem exata da estrutura ICC S5 de 32 bytes.
2. **[X] Patch nos Drivers Linux:** Aplicado no `ps4-bpcie-icc.c` e `ps4-apcie-icc.c`. Os drivers agora montam o payload de 32 bytes e imprimem o `hex dump` da resposta (`reply`) retornada pelo MCU.
3. **[ ] [PENDENTE] Teste ao vivo e compilação do bzImage:** Código modificado nos drivers. A compilação da imagem bzImage e o teste no PS4 real foram mantidos como **pendência gravada** para execução futura mediante autorização explícita.
