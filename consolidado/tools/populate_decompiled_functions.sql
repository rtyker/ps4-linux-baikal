-- Popula tabela decompiled_functions a partir do inventario consolidado/decompiled/INDEX.md
-- Meant to be run via: sqlite3 consolidado/ps4_hardware_memory.db < populate_decompiled_functions.sql

DROP TABLE IF EXISTS decompiled_functions;

CREATE TABLE decompiled_functions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    addr_hex TEXT NOT NULL UNIQUE,
    addr_full TEXT NOT NULL,
    short_name TEXT NOT NULL,
    category TEXT NOT NULL,
    role TEXT,
    file_path TEXT NOT NULL,
    lines INTEGER,
    status TEXT NOT NULL,
    validated_by_test_id INTEGER,
    notes TEXT,
    FOREIGN KEY (validated_by_test_id) REFERENCES test_history(id)
);

-- MTS driver (dc5a*) - PCI/attach
INSERT INTO decompiled_functions (addr_hex, addr_full, short_name, category, role, file_path, lines, status, notes) VALUES
('dc5a0070','0xffffffffdc5a0070','dc5a0070','MTS','mtsc_pci_attach - entrada PCI probe','decompiled/mtsc_pci_attach_dc5a0070.txt',199,'bruto','3 versoes: .txt, _ghidra, _asm'),
('dc5a34f0','0xffffffffdc5a34f0','dc5a34f0','MTS','mts_attach - attach de interface de rede','decompiled/mts_attach_dc5a34f0.txt',99,'bruto',''),
('dc5a41d0','0xffffffffdc5a41d0','dc5a41d0','MTS','SceGbeMtsCtrl_attach - attach MAC GBE','decompiled/legacy_raiz/decompiled_gbe_mac_attach.txt',95,'bruto',''),
('dc5a44c0','0xffffffffdc5a44c0','dc5a44c0','MTS','SceGbeMtsPhyCtrl_attach - thread gbe_phy_ctrl','decompiled/legacy_raiz/decompiled_gbe_phy_attach.txt',161,'revisado','Teste #52 validou loop de 20s/201*100ms contra esta funcao'),

-- Mac start/stop/calib
('dc5a0ba0','0xffffffffdc5a0ba0','dc5a0ba0','MTS','gbe_phy_calibration - loop 66 it (0x1bc-0x1d4)','decompiled/legacy_raiz/decompiled_dc5a0ba0_gbe_phy_calib.txt',530,'bruto',''),
('dc5a0c80','0xffffffffdc5a0c80','dc5a0c80','MTS','sub-rotina de calibração PHY','decompiled/legacy_raiz/decompiled_dc5a0c80.txt',444,'bruto',''),
('dc5a3060','0xffffffffdc5a3060','dc5a3060','MTS','mac_stop - parada do MAC','decompiled/legacy_raiz/decompiled_dc5a3060.txt',83,'refutado','Refutado em GBE_BRINGUP_DEEP_ANALYSIS.md secao 3.6: offsets 0x54/0x34/0x38 sao BAR0 MAC, NAO PCI config'),
('dc5a31f0','0xffffffffdc5a31f0','dc5a31f0','MTS','mac_enable - start do MAC (par de dc5a3060)','decompiled/legacy_raiz/decompiled_dc5a31f0.txt',126,'revisado','Sequencia correta em MTS_INIT_SEQUENCE_dc5a31f0.md'),
('dc5a3810','0xffffffffdc5a3810','dc5a3810','MTS','desconhecido - provavel mts_open ou sub-rotina','decompiled/legacy_raiz/decompiled_dc5a3810.txt',254,'bruto',''),
('dc5a58d0','0xffffffffdc5a58d0','dc5a58d0','MTS','handshake RMU - seta bit 2 de BAR0+0x34','decompiled/legacy_raiz/decompiled_dc5a58d0.txt',72,'bruto','Teste #53 tentou probe do bit2 - 0x34 nao retem valor'),

-- TX/RMU/Frame
('dc5a2680','0xffffffffdc5a2680','dc5a2680','MTS','papel desconhecido','decompiled/legacy_raiz/decompiled_dc5a2680.txt',102,'bruto',''),
('dc5a2bd0','0xffffffffdc5a2bd0','dc5a2bd0','MTS','provavel setup de descritor','decompiled/legacy_raiz/decompiled_dc5a2bd0.txt',164,'bruto','11 vars locais'),
('dc5a2d00','0xffffffffdc5a2d00','dc5a2d00','MTS','papel desconhecido','decompiled/legacy_raiz/decompiled_dc5a2d00.txt',46,'bruto',''),
('dc5a5ae0','0xffffffffdc5a5ae0','dc5a5ae0','MTS','papel desconhecido','decompiled/legacy_raiz/decompiled_dc5a5ae0.txt',199,'bruto',''),
('dc5a5ec0','0xffffffffdc5a5ec0','dc5a5ec0','MTS','RMU frame build - frame 34B magic 0xfa42','decompiled/legacy_raiz/decompiled_dc5a5ec0.txt',186,'revisado','Teste #54: frame reconstruido linhas 131-148'),

-- Helpers (dc5b*)
('dc5ba5e0','0xffffffffdc5ba5e0','dc5ba5e0','MTS_helper','res_alloc_helper - alocador','decompiled/res_alloc_helper_dc5ba5e0.txt',87,'bruto','chamado por attach de varios drivers'),

-- GBE clk/phy (dc52*, dc53*)
('dc526a60','0xffffffffdc526a60','dc526a60','GBE','boolean - papel desconhecido','decompiled/legacy_raiz/decompiled_dc526a60.txt',7,'bruto',''),
('dc526da0','0xffffffffdc526da0','dc526da0','GBE','papel desconhecido','decompiled/legacy_raiz/decompiled_dc526da0.txt',41,'bruto',''),
('dc526e40','0xffffffffdc526e40','dc526e40','GBE','stepping checker - val & 0xff0000 == 0x30000','decompiled/legacy_raiz/decompiled_dc526e40.txt',10,'revisado','Confirmado GBE_BRINGUP secao 2.B'),
('dc528600','0xffffffffdc528600','dc528600','ICC','icc_power - dispatcher (6 handlers via dc574150)','decompiled/icc_power_dc528760.txt',33,'revisado','ultimo handler dc528ef0 = 4/0x38 GBE power-on'),
('dc530200','0xffffffffdc530200','dc530200','GBE','papel desconhecido','decompiled/legacy_raiz/decompiled_dc530200.txt',110,'bruto',''),
('dc536580','0xffffffffdc536580','dc536580','GBE','funcao grande com varias sub-rotinas','decompiled/legacy_raiz/decompiled_dc536580.txt',139,'bruto',''),

-- ICC (dc7c8*, dc478*, dc3f5*)
('dc7c8b80','0xffffffffdc7c8b80','dc7c8b80','ICC','icc_device_power_main - dispatcher ICC','decompiled/icc_device_power_main_dc7c8b80.txt',124,'bruto',''),
('dc7c8a30','0xffffffffdc7c8a30','dc7c8a30','ICC','icc_devpower_set (variante dc7c8860)','decompiled/icc_devpower_set_dc7c8a30.txt',55,'bruto',''),
('dc7c8a70','0xffffffffdc7c8a70','dc7c8a70','ICC','icc_devpower_set (variante B)','decompiled/icc_devpower_set_dc7c8a70.txt',21,'bruto',''),
('dc7c8a00','0xffffffffdc7c8a00','dc7c8a00','ICC','papel desconhecido','decompiled/legacy_raiz/decompiled_dc7c8a00.txt',31,'bruto',''),
('dc7c8fb0','0xffffffffdc7c8fb0','dc7c8fb0','ICC','icc_devpower_get','decompiled/icc_devpower_get_dc7c8fb0.txt',29,'bruto',''),
('dc478a70','0xffffffffdc478a70','dc478a70','ICC','alias icc_power_set - wrapper ICC','decompiled/legacy_raiz/decompiled_icc_power_set.txt',21,'bruto','provavel alias de dc7c8a70'),
('dc478b80','0xffffffffdc478b80','dc478b80','ICC','provavel clone de dc7c8b80','decompiled/legacy_raiz/decompiled_icc_power.txt',124,'bruto',''),
('dc3f5400','0xffffffffdc3f5400','dc3f5400','ICC','incompleto (13 linhas)','decompiled/legacy_raiz/decompiled_dc3f5400.txt',13,'bruto',''),

-- Glue/Baikal PCIe (dc6df, dc718, dc719)
('dc6df850','0xffffffffdc6df850','dc6df850','Glue','glue_block_reset - confirmou bloco 0x2000 = GBE','decompiled/baikal_glue_block_reset_dc6df.txt',82,'revisado','2026-07-25: hold=0x180020 pulse=0x180074 (nao 0x180034)'),
('dc718710','0xffffffffdc718710','dc718710','Glue','glue_write - write primitive','decompiled/baikal_glue_write_dc718710.txt',17,'revisado',''),
('dc718d20','0xffffffffdc718d20','dc718d20','PCIe','baikal_pcie_probe','decompiled/baikal_pcie_probe.txt',53,'bruto',''),
('dc718eb0','0xffffffffdc718eb0','dc718eb0','PCIe','baikal_pcie_attach','decompiled/baikal_pcie_attach.txt',84,'bruto','3 versoes (.txt, _ghidra, _asm)'),
('dc7190d0','0xffffffffdc7190d0','dc7190d0','PCIe','clock init - escreve BAR2+0x10a030=(reg&0xfffffe07)|0xd8','decompiled/legacy_raiz/decompiled_dc7190d0.txt',32,'revisado','Causou tela preta prematuro no Linux (ver GBE_BRINGUP secao 2.B)'),

-- PHY init de outros dispositivos (referencia cruzada)
('dc72bfb0','0xffffffffdc72bfb0','dc72bfb0','PHY_REF','SATA PHY init - modelo para GBE PHY','decompiled/baikal_sata_phy_init_dc72bfb0.txt',1106,'bruto',''),
('dc7db0b0','0xffffffffdc7db0b0','dc7db0b0','PHY_REF','USB PHY init - modelo para GBE PHY','decompiled/baikal_usb_phy_init_dc7db0b0.txt',570,'bruto',''),

-- MSK (driver Yukon generico - competidor)
('dc4cdfc0','0xffffffffdc4cdfc0','dc4cdfc0','MSK','msk_attach','decompiled/msk_attach_dc4cdfc0.txt',55,'bruto','driver Yukon Aeolia/Belize'),
('dc4c5140','0xffffffffdc4c5140','dc4c5140','MSK','mskc_attach','decompiled/mskc_attach_dc4c5140.txt',241,'bruto',''),
('dc4cdee0','0xffffffffdc4cdee0','dc4cdee0','MSK','msk handler','decompiled/msk_dc4cdee0.txt',154,'bruto',''),

-- Funcoes residuais (provavelmente fora do escopo MTS)
('dc957e10','0xffffffffdc957e10','dc957e10','UNKNOWN','papel desconhecido - NAO confirmado MTS','decompiled/legacy_raiz/decompiled_dc957e10.txt',67,'bruto',''),
('dc95a780','0xffffffffdc95a780','dc95a780','UNKNOWN','papel desconhecido - NAO confirmado MTS','decompiled/legacy_raiz/decompiled_dc95a780.txt',49,'bruto',''),
('dc95a950','0xffffffffdc95a950','dc95a950','UNKNOWN','papel desconhecido - NAO confirmado MTS','decompiled/legacy_raiz/decompiled_dc95a950.txt',20,'bruto','');

-- =================== LACUNAS (ainda nao decompiladas - validadas em testes ao vivo) ===================
INSERT INTO decompiled_functions (addr_hex, addr_full, short_name, category, role, file_path, lines, status, validated_by_test_id, notes) VALUES
('dc5a2840','0xffffffffdc5a2840','dc5a2840','MTS_LACUNA','MDIO read high word (bits 31:16)','PENDING',NULL,'pendente',61,'Validado por teste #61: Correcao Clause 22 MDIO BMCR=0x1040'),
('dc5a2950','0xffffffffdc5a2950','dc5a2950','MTS_LACUNA','MDIO write opcode 0x2000 (wait bit 15=0)','PENDING',NULL,'pendente',61,'Validado por teste #61'),
('dc5a4950','0xffffffffdc5a4950','dc5a4950','MTS_LACUNA','gatilho BAR0+0x1c = 0x80000000 (ativou motor MAC/PHY 0x0->0x80030000)','PENDING',NULL,'pendente',59,'Validado por teste #59 - HARDWARE_TRIGGER_BAR0_1C_CONFIRMADO'),
('dc5a4e90','0xffffffffdc5a4e90','dc5a4e90','MTS_LACUNA','relacionado ao RMU/dc5a5200','PENDING',NULL,'pendente',60,''),
('dc5a5050','0xffffffffdc5a5050','dc5a5050','MTS_LACUNA','provavel proximo chamado de dc5a4e90','PENDING',NULL,'pendente',NULL,''),
('dc5a5200','0xffffffffdc5a5200','dc5a5200','MTS_LACUNA','RMU sub-header 0x9807 (offset 26/27 do frame)','PENDING',NULL,'pendente',60,'Validado por teste #60 - RMU_SUBHEADER_9807'),
('dc5a6290','0xffffffffdc5a6290','dc5a6290','MTS_LACUNA','sub-rotina vista em chamada','PENDING',NULL,'pendente',NULL,''),

('dc5ba8d0','0xffffffffdc5ba8d0','dc5ba8d0','MTS_HELPER_LACUNA','aloca BARs (chamado por dc718eb0)','PENDING',NULL,'pendente',NULL,''),
('dc5baa30','0xffffffffdc5baa30','dc5baa30','MTS_HELPER_LACUNA','cria ifnet (chamado por dc5a0070)','PENDING',NULL,'pendente',NULL,''),

('dc6dfb60','0xffffffffdc6dfb60','dc6dfb60','GLUE_LACUNA','primitiva reset do glue (chamado por dc6df850(0x4000) e 0x2000)','PENDING',NULL,'pendente',NULL,''),
('dc7187a0','0xffffffffdc7187a0','dc7187a0','GLUE_LACUNA','glue read (chamado em dc72bfb0 SATA PHY init)','PENDING',NULL,'pendente',NULL,''),
('dc7187d0','0xffffffffdc7187d0','dc7187d0','GLUE_LACUNA','glue read (chamado em dc6df850)','PENDING',NULL,'pendente',NULL,''),
('dc718800','0xffffffffdc718800','dc718800','GLUE_LACUNA','glue write (chamado em dc6df850)','PENDING',NULL,'pendente',NULL,''),

('dc3f5bd0','0xffffffffdc3f5bd0','dc3f5bd0','ICC_LACUNA','wrapper icc_query(4, 0x38) - FUNDAMENTAL','PENDING',NULL,'pendente',NULL,'Referenciado em GBE_BRINGUP secao 2.A como funcao que envia ICC ao Syscon'),
('dc574150','0xffffffffdc574150','dc574150','ICC_LACUNA','registra handlers ICC (chamado 6x em dc528760)','PENDING',NULL,'pendente',NULL,''),
('dc528ef0','0xffffffffdc528ef0','dc528ef0','ICC_LACUNA','handler 4/0x38 = GBE power-on','PENDING',NULL,'pendente',NULL,''),

('dc529ed0','0xffffffffdc529ed0','dc529ed0','GBE_LACUNA','carta branca - origem desconhecida','PENDING',NULL,'pendente',NULL,''),
('dc529f40','0xffffffffdc529f40','dc529f40','GBE_LACUNA','carta branca - origem desconhecida','PENDING',NULL,'pendente',NULL,''),
('dc52a4f0','0xffffffffdc52a4f0','dc52a4f0','GBE_LACUNA','carta branca - origem desconhecida','PENDING',NULL,'pendente',NULL,'');

-- Index para consultas rapidas
CREATE INDEX IF NOT EXISTS idx_df_addr ON decompiled_functions(addr_hex);
CREATE INDEX IF NOT EXISTS idx_df_category ON decompiled_functions(category);
CREATE INDEX IF NOT EXISTS idx_df_status ON decompiled_functions(status);

-- View resumo
CREATE VIEW IF NOT EXISTS v_decompiled_summary AS
    SELECT category, status, COUNT(*) as qty FROM decompiled_functions GROUP BY category, status ORDER BY category, status;
