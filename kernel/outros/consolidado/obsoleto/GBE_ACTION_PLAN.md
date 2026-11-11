# Plano de Ação GBE: Fase 3 — Neutralização do Shutdown do Orbis

## O Estado Atual
- **Teste M1-M7 (ICC/MMIO Power-on):** Refutados. Nenhum payload ICC liga a GBE via Linux.
- **Teste M8-M12 (BAR2 Pervasive):** Refutados. A GBE já tem status de energia idêntico ao de SATA/USB no barramento PCIe; não está presa num estado de hold/pulse da glue logic.
- **Teste M13 (Payloads seguros Major 5):** Refutados. WLAN/BT sobrevivem perfeitamente a comandos ICC, mas GBE continua com ChipID `00`.
- **A Grande Descoberta (Payload orbis-hw-dumper):** O nosso próprio payload executado em Ring 0 no Orbis ANTES do Linux bootar já relata o BAR0 da GBE como ZERADO. Isso significa que **a GBE não cai por causa do Linux, mas sim porque o kernel Orbis (FreeBSD) desliga o driver (`SceGbeMtsCtrl`) durante o preparativo do kexec (shutdown/detach).** O Linux apenas herda o hardware frio.

## Novo Objetivo (Fase 3)
Neutralizar a rotina de `detach` / `shutdown` do driver `SceGbeMtsCtrl` dentro da memória do Orbis *antes* que o payload do kexec a invoque. 
Se o Orbis for impedido de desligar a GBE, o Linux herdará o hardware no estado nativo funcional (energizado).

## Passos para Implementação
1. **Engenharia Reversa (Estática):** Analisar o `kmem_dump_1252.bin` para localizar a tabela de métodos do `SceGbeMtsCtrl`.
2. **Identificação do Alvo:** Encontrar o endereço exato das funções `detach` e `shutdown` deste driver.
3. **Criação do Patch (Em Memória):** Adaptar o payload do Orbis (ex: `orbis-hw-dumper` ou o loader do kexec) para escrever `0xC3` (`ret`) no primeiro byte da função `detach`/`shutdown` do `SceGbeMtsCtrl`.
4. **Teste ao Vivo:** Dar boot pelo payload modificado. Se funcionar, o Linux finalmente vai ler o ChipID corretamente no boot e o eth0 subirá.

## Próxima Ação Imediata
Executar análise no `kmem_dump_1252.bin` com `radare2` para mapear a `device_method_t` table da GBE.
