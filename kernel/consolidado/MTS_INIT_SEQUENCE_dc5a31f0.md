# Sequência completa de inicialização do MAC — `mts_init()` (`fcn.ffffffffdc5a31f0`)

> Especificação extraída da decompilação do kernel Orbis 12.52 (`consolidado/decompiled_dc5a31f0.txt`),
> cruzada com medições ao vivo da BAR0 (Fases 13/14, 2026-07-22).
> Driver de origem: `W:\Build\J02690760\sys\freebsd\sys\dev\mts\if_mts.c` — **MTS, não Marvell Yukon**.
> Chamada pelo handler de `SIOCSIFFLAGS` (`dc5a3810`) no `ifconfig up`, **não** pelo attach.

---

## 1. Pseudocódigo em ordem de execução

```c
void mts_init(device_t dev)                      // fcn.ffffffffdc5a31f0
{
    ifp = *dev;
    if (ifp[0x1c8] & 0x40) return;               // já RUNNING → não faz nada
    sc  = dev[0x10];                             // softc

    /* --- A. anel TX --------------------------------------------------- */
    sc[0x3058] = 0;                              // índice/produtor TX
    sc[0x3060] = 0x100;                          // 256 descritores
    memset(sc[0x38], 0, 0x1000);                 // zera anel TX (4 KB)

    p = sc[0x38];                                // VA do anel TX
    for (i = -0x1800; i != 0; i += 0x18) {       // 0x1800/0x18 = 256 entradas
        sc[0x1868 + i]     = p;                  // sw desc -> hw desc
        p[0]               = 0x80000000;         // OWN = hardware
        p                 += 4;                  // +16 bytes (desc = 16 B)
        sc[0x1868+i][8]   |= 0xffff0000;         // campo em +8
        sc[0x1858 + i]     = 0;                  // limpa slot de mbuf
    }
    if (sc[0x28]) bus_dmamap_sync(sc[0x08], sc[0x28], 5);   // PRE_READ|PRE_WRITE

    /* --- B. anel RX --------------------------------------------------- */
    sc[0x3064] = 0;                              // índice RX
    memset(sc[0x48], 0);                         // zera anel RX

    base = sc[0x48];                             // VA do anel RX
    pd = &sc[0x1868];
    for (off = 0, bo = 0; off != 0x1000; off += 0x10, bo += 0x600) {
        *pd            = base + off;             // sw desc -> hw desc
        *(base + off)  = 0x80000600;             // OWN + tamanho 0x600 (1536 B)
        *(*pd + 4)     = sc[0x32C8] + bo;        // endereço físico do buffer
        if (off == 0xff0) **pd |= 0x40000000;    // WRAP no último descritor
        d = *pd;  pd += 3;                       // stride 24 B na sw array
        *d &= 0x7fffffff;                        // limpa OWN (entrega ao driver)
    }
    if (sc[0x30]) bus_dmamap_sync(sc[0x10], sc[0x30], 5);

    /* --- C. escritas na BAR0, NESTA ORDEM ----------------------------- */
    BAR0[0x44] = sc[0x40];                       // TX ring, endereço FÍSICO
    BAR0[0x3c] = sc[0x40];                       //   idem (ver §3)
    BAR0[0x48] = sc[0x50];                       // RX ring, endereço FÍSICO
    BAR0[0x40] = sc[0x50];                       //   idem (ver §3)
    BAR0[0x34] |= 1;                             // enable MAC core 1
    BAR0[0x38] |= 1;                             // enable MAC core 2
    BAR0[0x54]  = sc[0x3098];                    // máscara de interrupção (IMR)

    /* --- D. finalização ----------------------------------------------- */
    sc[0x309c]  = 0;
    ifp[0x1c8]  = (ifp[0x1c8] & 0xfffffbbf) | 0x40;   // marca RUNNING
}
```

---

## 2. Layout do softc (deduzido, e consistente com o uso)

| offset | conteúdo |
|---|---|
| `0x08` | DMA tag TX |
| `0x10` | DMA tag RX |
| `0x28` | DMA map TX |
| `0x30` | DMA map RX |
| `0x38` | anel TX — endereço **virtual** |
| `0x40` | anel TX — endereço **físico** (vai para a BAR0) |
| `0x48` | anel RX — endereço **virtual** |
| `0x50` | anel RX — endereço **físico** (vai para a BAR0) |
| `0x68`…`0x1868` | array de descritores de software TX — 256 × 24 B = `0x1800` |
| `0x1868`…`0x3068` | array de descritores de software RX — 256 × 24 B = `0x1800` |
| **`0x3068`** | **recurso bus_space da BAR0** (par tag/handle) |
| `0x3098` | valor da IMR escrito em `BAR0+0x54` |
| `0x309c` | zerado no fim |
| `0x32C8` | base **física** da área de buffers RX |
| `0x3058` / `0x3064` | índices TX / RX |
| `0x3060` | `0x100` = 256 descritores |

**Verificação de consistência:** os dois arrays de software ocupam exatamente `0x68`→`0x3068`, terminando precisamente onde fica o recurso da BAR0. Isso confirma tanto o stride de 24 bytes quanto a contagem de 256 descritores — dois cálculos independentes que fecham.

---

## 3. Achado importante: `0x3c`/`0x44` e `0x40`/`0x48` são pares base/ponteiro

O código escreve o **mesmo valor** em `0x44` e `0x3c` (`sc[0x40]`), e o **mesmo valor** em `0x48` e `0x40` (`sc[0x50]`). Mas ao vivo eles leem **diferente**:

| offset | lido ao vivo | interpretação |
|---|---|---|
| `0x44` | `0x10000000` | **base** do anel TX |
| `0x3c` | `0x10000f70` | ponteiro corrente TX (avançou `0xf70`) |
| `0x48` | `0x10004000` | **base** do anel RX |
| `0x40` | `0x100042a0` | ponteiro corrente RX (avançou `0x2a0`) |

Ou seja: escreve-se o mesmo endereço nos dois, e o hardware **avança** o de ponteiro conforme consome descritores. Isso é corroborado pela medição da Fase 14: após o enable, `0x40` foi de `0x100042a0` → `0x100043c0` (avanço de `0x120`) — o hardware mexeu nele sozinho.

**Consequência de segurança (medida):** os anéis ficam nos físicos `0x10000000` (TX) e `0x10004000` (RX). O `/proc/iomem` ao vivo mostra `00700000-7efe7fff : System RAM` — ambos caem **dentro de RAM que o Linux usa**. São os anéis da era Orbis, sobreviventes do kexec. Habilitar Bus Master sem reprogramar esses registradores faria o MAC ler/escrever nessa memória.

---

## 4. Formato dos descritores (16 bytes)

**TX** — `desc[0] = 0x80000000` (OWN=hw), `desc[+8] |= 0xffff0000`.

**RX** — `desc[0] = 0x80000600` → bit 31 OWN + tamanho `0x600` (1536 B); `desc[+4] =` endereço físico do buffer; último descritor recebe `| 0x40000000` (WRAP); depois `&= 0x7fffffff` limpa OWN.

Área de buffers RX: 256 × `0x600` = `0x60000` (384 KB), base física em `sc[0x32C8]`.

Bits: **31 = OWN**, **30 = WRAP**, **[10:0] = tamanho**.

---

## 5. O que já foi validado ao vivo, e o que falta

| passo | estado |
|---|---|
| `BAR0[0x34] \|= 1` / `BAR0[0x38] \|= 1` | ✅ **executado e confirmado** (Fase 14): produziu mudança real e persistente em `0x38`, `0x40`, `0x50`, `0x5c`, `0x70` |
| escritas em `0x3c`/`0x40`/`0x44`/`0x48` | ❌ não feitas — exigem anéis DMA alocados pelo kernel |
| montagem dos anéis TX/RX | ❌ impossível por `dd`/userspace |
| `BAR0[0x54]` (IMR) | ❌ valor vem de `sc[0x3098]`, não conhecido |
| MDIO/PHY | ⚠️ sonda da Fase 15 **não** completou transação (ver `memory/devmem-nao-existe-usar-dd-octal.md`) |

**Conclusão:** o enable isolado (`0x34`/`0x38`) já demonstra efeito real no hardware, mas a sequência só faz sentido completa — os registradores de anel precisam apontar para memória DMA que o **Linux** possua. Isso encerra o que dá para fazer por telnet: **daqui em diante é código de driver**.

---

## 6. Ordem obrigatória para o driver

1. alocar (`dma_alloc_coherent`) anel TX de 4 KB, anel RX de 4 KB e 384 KB de buffers RX;
2. montar os 256 descritores TX (OWN=hw) e os 256 RX (buffers + WRAP no último, OWN limpo);
3. sincronizar os mapas DMA;
4. escrever `BAR0[0x44]` e `BAR0[0x3c]` = físico do anel TX;
5. escrever `BAR0[0x48]` e `BAR0[0x40]` = físico do anel RX;
6. `BAR0[0x34] |= 1`; `BAR0[0x38] |= 1`;
7. escrever a IMR em `BAR0[0x54]`;
8. `pci_set_master()` — **só aqui**, nunca antes dos passos 4–5, senão o MAC faz DMA nos anéis herdados do Orbis.

O passo 8 não existe no `dc5a31f0` porque no Orbis o Bus Master já estava ligado desde o attach. No Linux ele está **desligado** (`COMMAND=0x0542` vs `0x0546` dos periféricos que funcionam), o que hoje é uma proteção — e deve continuar assim até os passos 4–5 estarem corretos.
