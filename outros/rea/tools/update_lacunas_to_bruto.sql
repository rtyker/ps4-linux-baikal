-- Atualiza status das lacunas: depois da Fase 3, agora status='bruto' e path aponta para extracted/
-- Aplica aos 19 enderecos extraidos.

UPDATE decompiled_functions SET
    status = 'bruto',
    file_path = 'decompiled/extracted/decompiled_' || addr_hex || '.txt',
    notes = COALESCE(notes, '') || ' [Extraido por PyGhidra em 2026-07-24]'
WHERE status = 'pendente'
  AND addr_hex IN (
    'dc5a2840','dc5a2950','dc5a4950','dc5a4e90','dc5a5050',
    'dc5a5200','dc5a6290',
    'dc5ba8d0','dc5baa30',
    'dc6dfb60','dc7187a0','dc7187d0','dc718800',
    'dc3f5bd0','dc574150','dc528ef0',
    'dc529ed0','dc529f40','dc52a4f0'
  );

-- Bump sizes lines e adiciona role mais detalhado a partir do header do arquivo extraido
UPDATE decompiled_functions SET
    role = 'MDIO read high word (32-bit read devad=1 reg=0)',
    notes = 'LACUNA resolvida 2026-07-24 via PyGhidra. Tamanho 865 instr.'
WHERE addr_hex = 'dc5a5200';

UPDATE decompiled_functions SET
    role = 'wrapper icc_query(major, minor) - envia ICC ao Syscon. 34 callers confirmados. FUNDAMENTAL'
WHERE addr_hex = 'dc3f5bd0';

UPDATE decompiled_functions SET
    role = 'registra handlers ICC - chamado 94x (todos os drivers). 2 callees.'
WHERE addr_hex = 'dc574150';

UPDATE decompiled_functions SET
    role = 'handler 4/0x38 = GBE power-on. Sem callers (registrado via callback).'
WHERE addr_hex = 'dc528ef0';
