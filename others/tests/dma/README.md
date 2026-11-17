# Roteiros de teste ao vivo do DMA / SPM (PS4 ligado, Linux rodando)

Todos rodam **no PS4** por SSH, sem copiar nada antes: o roteiro é lido do PC pela entrada padrão.

```bash
sshpass -p ps4 ssh root@192.168.6.128 bash -s <ARGUMENTO> < others/tests/dma/<roteiro>.sh
```

Cada verificação imprime `PASS` ou `FAIL`; no fim, o total. Todos **restauram** o que tocam (janela da SPM
em zero, módulo do HD recarregado) por um `trap`, mesmo se algo falhar no meio.

| Roteiro | Argumento | O que faz |
|---|---|---|
| `validate_first_boot.sh` | nenhum | Só leitura. Confere kernel em execução, módulo carregado no boot, estado do DMA, 1 MiB a quente, leitura desalinhada, lacuna e erros no `dmesg`. Use logo depois de gravar uma tag nova no HD. |
| `full_battery.sh` | caminho do `baikal-memory.ko` no PS4 | Bateria completa do `baikal-memory` (T1 a T9 do plano `PLANO_BAIKAL_MEMORY_DMA`), falhas injetadas, recuperação e 2 leitores simultâneos. **Escreve** na janela validada (SPM `0x200000`, 64 KiB) e nos 2 KiB do fim da janela, salvando e restaurando. |
| `fault_and_regress.sh` | caminho do `baikal-memory.ko` | Injeção de falha (`dma_fault_inject` 2 = erro real do DMAC, 1 = aborto simulado) e regressão do caminho normal. |
| `bar5_paired.sh` | nenhum (usa o módulo do HD) | Controle pareado para provar que escrever no fim da janela não mexe na BAR5 (a BAR5 muda sozinha, então o hash dela não serve). |
| `blk_test.sh` | caminho do `baikal-spm-blk.ko` | Dispositivo de bloco `/dev/baikal_spm0`: integridade `O_DIRECT` (setores desalinhados, > 1 MiB), dispositivo inteiro, cache de página, vazão, modo só-CPU, limites. |
| `swap_test.sh` | caminho do `baikal-spm-blk.ko` | Swap de verdade: processos confinados por cgroup (`MemoryMax`) paginam pela SPM e cada bloco de 1 MiB é conferido por CRC. 1 processo, 3 concorrentes e DMA desligado. |

## Armadilhas (todas já custaram tempo)

- **`dd of=-` não escreve na saída padrão**: cria um arquivo chamado `-`. Para hash, omita o `of=`.
- **Não filtre o `dmesg` por timestamp com `awk '$1'`**: abaixo de 10000 s o kernel imprime `[ 7475.6…]` com espaço
  depois do `[`. Leia por contagem de linhas (`N=$(dmesg | wc -l)` e depois `dmesg | tail -n +$((N+1))`).
- **O relógio do PS4 fica minutos atrás do PC** (importa ao correlacionar `dmesg -T` com a hora do que você rodou).
- **Restaurar zeros com `head -c N /dev/zero | dd bs=64k count=1` grava só parte** (o `dd` lê o pipe uma vez). Use arquivo.
- **`allow_write` do `baikal-memory` é `0444`**: só muda recarregando o módulo.
- **Não compile módulo fora da árvore enquanto o build oficial roda**: os dois usam `kernel/kernel_build_7.0`.
- **Teste de `deploy-boot-7.0.sh` só em tmpfs (`/dev/shm`)**: no fim ele desmonta as partições do mesmo disco do destino.

Os roteiros de bloco e de swap precisam do `baikal_dmac` carregado para usar DMA; sem ele funcionam pela CPU (~20× mais lento).
