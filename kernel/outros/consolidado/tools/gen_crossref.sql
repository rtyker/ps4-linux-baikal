-- Gera CROSSREF.md automaticamente: lista cada função + seus callers/callees
-- saida markdown com bullets
.mode list
.separator "\n"
.headers off

ATTACH 'consolidado/ps4_hardware_memory.db' AS db;

WITH RECURSIVE
addr_extract(text) AS (
  SELECT 'placeholder'
)
SELECT '';
