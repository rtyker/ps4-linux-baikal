# Registro de Experimentos e Patches: Ethernet Baikal GBE
**Objetivo:** Viabilizar a placa de rede embutida no Southbridge Baikal do PS4 Pro (`00:14.1 [104d:90d8]`). Inicialmente acreditava-se ser Marvell Yukon 2 (`sky2`), mas foi posteriormente identificada como Synopsys DWMAC (`stmmac`).

---

## TENTATIVA 1: Identificação do Silício (Concluída)
- **Problema Relatado:** O kernel parava no `probe` com o erro `unsupported chip type 0x0`. A placa retornava falha de inicialização (`error -95`).
- **Análise Técnica (Mapeamento Direto):** Usando um programa de diagnóstico C para acessar o barramento via `mmap` (mapeamento do `BAR0`), determinou-se que os registradores `B2_CHIP_ID` (offset `0x11b`) e `B2_MAC_CFG` (offset `0x11c`) estavam retornando zeros literais (`0x00`) nativamente, em vez de um identificador Marvell válido. A memória em si estava operante (registradores básicos operacionais).
- **Ação Tomada:** Injeção de patch no script de compilação `00-build-kernel.sh` (Python replace) forçando o valor dos registradores no struct `hw`:
  - `hw->chip_id = CHIP_ID_YUKON_EX;`
  - `hw->chip_rev = CHIP_REV_YU_EX_B0;`
- **Resultado:** Parcial. A placa foi corretamente reconhecida como "Yukon-2 Extreme chip revision 2", configurou as IRQs (`bpcie_assign_irqs returning 1`), mas imediatamente depois abortou com um novo erro: "No interrupt generated using MSI, switching to INTx mode" seguido novamente do erro `-95`.

---

## TENTATIVA 2: Teste Sintético MSI - Falha do Regex (Concluída)
- **Problema Relatado:** O driver tenta alocar interrupção MSI e logo executa um teste (`sky2_test_msi`) que força a geração de uma IRQ via software (`Y2_IS_IRQ_SW`). No hardware customizado da Sony, esse teste reprova e falha.
- **Análise Técnica (Análise de Código):**
  - O código original do Linux tentaria reverter para INTx se o MSI falhasse e seguiria adiante. No entanto, no PS4, INTx não tem roteamento físico viável.
  - O kernel customizado para PS4 tem um bloco rígido (`#ifdef CONFIG_X86_PS4`) para forçar o MSI via `apcie_assign_irqs`. Neste bloco, se o teste falha, há uma instrução `goto err_out_free_netdev` sem possibilidade de bypass, abortando totalmente a inicialização da placa.
- **Ação Tomada:** Modificação do `00-build-kernel.sh` para injetar a neutralização do erro no teste de MSI com a seguinte lógica:
  `if (pdev->device == PCI_DEVICE_ID_SONY_BAIKAL_GBE) { err = 0; }`
- **Resultado:** Fracasso operacional. A RegEx injetada no script de compilação encontrou o padrão `if (!disable_msi && pci_enable_msi(pdev) == 0)` (que é o caminho padrão do Linux) e modificou esse trecho em vez do trecho dentro de `#ifdef CONFIG_X86_PS4`. Consequentemente, durante a execução no PS4, o kernel usou o bloco específico do PS4 original, rodou o teste não patcheado, falhou, acionou o `goto err_out_free_netdev` e abortou de novo com erro `-95`.

---

## TENTATIVA 3: Bypass MSI Global (Atualmente em Execução)
- **Problema Relatado:** Garantir que o bypass do erro seja aplicado no bloco de execução correto (onde ocorre a chamada de alocação de interrupção da placa Sony).
- **Análise Técnica:** Em vez de tentar alinhar expressões regulares em um bloco específico, a solução mais limpa em engenharia de patches a quente (via texto) é substituir o comando base de teste globalmente.
- **Ação Tomada:** O script `00-build-kernel.sh` foi reescrito. Agora a substituição faz:
  `target2 = 'err = sky2_test_msi(hw);'`
  `replacement2 = 'err = sky2_test_msi(hw); if (pdev->device == PCI_DEVICE_ID_SONY_BAIKAL_GBE) { err = 0; }'`
- **Expectativa:** Quando a função `sky2_probe` rodar (independentemente do path ou do bloco `#ifdef`), o erro de teste sintético será perdoado e ignorado. O driver deve prosseguir para executar `register_netdev` e, em seguida, ativar e registrar a interface (`eth0` ou similar), mantendo a capacidade MSI ativada e pronta para receber o primeiro pacote real de hardware.

*Status: Concluída. Fracasso estrutural. O driver falhou em prosseguir ou comunicar com a placa mesmo com o bypass, provando que a placa física não responde aos comandos de controle da Marvell.*

---

## TENTATIVA 4: Correção Definitiva - Synopsys DWMAC (Em Andamento)
- **Problema Relatado:** As três tentativas anteriores falharam porque foram baseadas na premissa falsa de que a Sony continuou usando a arquitetura Marvell (Yukon-2) no Baikal, como fez no chipset Aeolia original. 
- **Nova Descoberta:** Foi descoberto que o silício do Baikal para o GBE é na verdade um **Synopsys DWMAC (stmmac)**. O driver `sky2` tentava configurar o chip escrevendo em registradores Marvell inexistentes, o que causava falha silenciosa seguida do erro de interrupção MSI (porque a placa nunca recebeu o comando real para habilitar o MSI em sua arquitetura).
- **Ação Tomada:** O script de build foi limpo de todas as gambiarras em Python do `sky2`. Uma nova injeção foi escrita para adicionar o `PCI_VENDOR_ID_SONY` (`104d:90d8`) na tabela do driver `stmmac_pci.c`, vinculando-o à estrutura de informações `snps_gmac5_pci_info`. As flags `CONFIG_STMMAC_ETH`, `CONFIG_STMMAC_PLATFORM` e `CONFIG_STMMAC_PCI` foram injetadas no script para forçar a compilação do driver correto.
- **Expectativa:** O kernel deverá inicializar a placa usando o driver nativo `stmmac`, reconhecendo a topologia DWMAC e mapeando a rede via PCIe Glue do Baikal sem necessidade de testes de bypass sintéticos.

*Status: Script atualizado. Aguardando a execução do script de compilação pelo usuário.*
