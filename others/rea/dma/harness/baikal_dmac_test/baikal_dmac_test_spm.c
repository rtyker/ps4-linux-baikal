// SPDX-License-Identifier: GPL-2.0
/*
 * baikal_dmac_test_spm — harness de RE: o DMAC do Baikal (00:14.5, 104d:90dc)
 * consegue LER a SPM/DDR3 (00:14.6, 104d:90dd, BAR2)?
 *
 * Passo 2 de others/rea/dma/plans/PLANO_DMA_SPM_DDR3_2026-11-16.md.
 * Cópia separada do baikal_dmac_test.c (o original não muda).
 *
 * SOMENTE LEITURA da SPM: o DMAC copia SPM -> buffer coerente do host.
 * Nada é escrito na SPM (o modo de escrita é o Passo 3 e só vem se este passar).
 *
 * O que o teste faz, por tamanho (256 B, 4 KiB, 64 KiB, 1 MiB; para na 1a falha):
 *   1. CPU lê o trecho da SPM com memcpy_fromio (referência + vazão CPU);
 *   2. DMAC copia o mesmo trecho para o buffer B (por polling, timeout 2 s);
 *   3. compara B com a leitura da CPU e confere a guarda de 4 KiB depois de B;
 *   4. CPU lê o trecho de novo: se mudou entre 1 e 4, a SPM está viva
 *      (outro agente escreve nela) e a comparação é marcada como inconclusiva.
 *
 * Endereço que o DMAC usa para a SPM (spm_base), só candidatos do plano:
 *   0x80000000 (H1: endereço PCI do BAR2, padrão) ou 0xC0000000 (H2: writeup
 *   do Debarshi). Qualquer outro valor é recusado. O BAR2 da SPM é mapeado
 *   para a leitura de referência da CPU e TEM que estar em 0x80000000, senão
 *   nada é armado.
 *
 * Pré-condições: rmmod baikal_dmac (disputam o 90dc). baikal-memory pode ficar
 * carregado (o harness só faz ioremap do BAR2, sem request_mem_region).
 *
 * Uso: insmod baikal_dmac_test_spm.ko run=1 [bar=0] [spm_base=0x80000000]
 *      [spm_offset=0] [maxkb=1024]
 */

#include <linux/module.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>

#define DMAC_UNK70     0x70
#define DMAC_INT_FLAG  0x80
#define DMAC_INT       0x84
#define DMAC_EN        0x88
#define DMAC_RST       0x8c
#define DMAC_DESC_ADDR 0x90
#define DMAC_UNK94     0x94
#define DMAC_CON       0x98
#define DMAC_SRC       0x9c
#define DMAC_DST       0xa0
#define DMAC_LEN       0xa4
#define DMAC_DESC_EN   0xa8
#define DMAC_DEBUG_ST  0xac

#define SPM_VENDOR     0x104d
#define SPM_DEVICE     0x90dd
#define SPM_PCI_BAR2   0x80000000UL
#define SPM_WINDOW     SZ_4M		/* mesma janela do baikal-memory */
#define GUARD          4096
#define FILL_B         0xee

static int run;
module_param(run, int, 0444);
MODULE_PARM_DESC(run, "1 = executa o teste (0 = só imprime registradores)");
static int bar;
module_param(bar, int, 0444);
MODULE_PARM_DESC(bar, "controlador do DMAC: 0 (DMAC1, padrão) ou 2 (DMAC2)");
static unsigned long spm_base = SPM_PCI_BAR2;
module_param(spm_base, ulong, 0444);
MODULE_PARM_DESC(spm_base, "endereço da SPM visto pelo DMAC: 0x80000000 (H1) ou 0xC0000000 (H2)");
static unsigned long spm_offset;
module_param(spm_offset, ulong, 0444);
MODULE_PARM_DESC(spm_offset, "offset na SPM (múltiplo de 64, dentro de 4 MiB)");
static unsigned int maxkb = 1024;
module_param(maxkb, uint, 0444);
MODULE_PARM_DESC(maxkb, "maior tamanho testado em KiB (até 1024)");
static int write;
module_param(write, int, 0444);
MODULE_PARM_DESC(write, "1 = DMA host->SPM (Passo 3). Só em spm_offset=0x200000, maxkb<=64");

/* Janela única onde o modo write pode escrever (validada em 2026-11-16). */
#define WR_OFF		0x200000UL
#define WR_MAX		SZ_64K

struct dmac_desc {
	__le32 src;
	__le32 dst;
	__le32 len;
	__le32 next;
};

struct ctx {
	struct device *dev;
	void __iomem *r;		/* registradores do DMAC */
	void __iomem *spm;		/* BAR2 da SPM (4 MiB) */
	u8 *b;				/* destino do DMA (coerente) */
	dma_addr_t dma_b;
	struct dmac_desc *d;
	dma_addr_t dma_d;
	size_t sz;
	bool leak;
	int pass, fail, inconcl;
};

static void dump_regs(struct device *dev, void __iomem *r, const char *tag)
{
	static const u32 offs[] = { DMAC_UNK70, DMAC_INT_FLAG, DMAC_INT, DMAC_EN,
		DMAC_RST, DMAC_DESC_ADDR, DMAC_UNK94, DMAC_CON, DMAC_SRC,
		DMAC_DST, DMAC_LEN, DMAC_DESC_EN, DMAC_DEBUG_ST };
	int i;

	dev_info(dev, "%s:\n", tag);
	for (i = 0; i < ARRAY_SIZE(offs); i++)
		dev_info(dev, "  +0x%02x = 0x%08x\n", offs[i], readl(r + offs[i]));
}

static int con_for(u32 or_all, u32 *con)
{
	unsigned int tz = __ffs(or_all | 0x80);

	if (tz < 2)
		return -EINVAL;
	*con = tz == 2 ? 0 : tz == 3 ? 0x10000 : tz == 4 ? 0x20000 :
	       tz == 5 ? 0x30000 : 0x40000;
	return 0;
}

/* Mesma sequência validada em 2026-11-13 (baikal_dmac_test.c), só polling. */
static int hw_xfer(struct ctx *c, u32 con, u64 *ns)
{
	void __iomem *r = c->r;
	unsigned long to;
	ktime_t t0;
	u32 f = 0;

	if (readl(r + DMAC_INT_FLAG) || readl(r + DMAC_INT) || readl(r + DMAC_DESC_EN) ||
	    readl(r + DMAC_EN) || readl(r + DMAC_DESC_ADDR)) {
		dev_err(c->dev, "controlador NAO ocioso; nada escrito\n");
		return -EBUSY;
	}
	writel(0, r + DMAC_LEN);
	writel(0, r + DMAC_SRC);
	writel(0, r + DMAC_DST);
	if (readl(r + DMAC_LEN) || readl(r + DMAC_SRC) || readl(r + DMAC_DST)) {
		dev_err(c->dev, "LEN/SRC/DST nao zeraram; abortando antes de armar\n");
		return -EIO;
	}
	writel(lower_32_bits(c->dma_d), r + DMAC_DESC_ADDR);
	writel(0, r + DMAC_INT_FLAG);
	writel(con, r + DMAC_CON);
	writel(0, r + DMAC_INT);
	wmb();
	t0 = ktime_get();
	writel(1, r + DMAC_DESC_EN);

	to = jiffies + msecs_to_jiffies(2000);
	while (time_before(jiffies, to)) {
		f = readl(r + DMAC_INT_FLAG);
		if (f & 0x1f)
			break;
		cpu_relax();
	}
	*ns = ktime_to_ns(ktime_sub(ktime_get(), t0));
	if (!(f & 0x1f)) {
		dev_err(c->dev, "TIMEOUT (INT_FLAG=0x%x DEBUG_ST=0x%x); reset e buffers mantidos\n",
			f, readl(r + DMAC_DEBUG_ST));
		goto reset;
	}
	if (f & 0x1e) {
		dev_err(c->dev, "ERRO do DMAC: INT_FLAG=0x%x DEBUG_ST=0x%x; buffers mantidos\n",
			f, readl(r + DMAC_DEBUG_ST));
		goto reset;
	}
	writel(f & ~0x1u, r + DMAC_INT_FLAG);
	return 0;
reset:
	writel(2, r + DMAC_RST);
	udelay(50);
	writel(0, r + DMAC_RST);
	c->leak = true;
	return (f & 0x1f) ? -EIO : -ETIMEDOUT;
}

static u64 mbps(size_t bytes, u64 ns)
{
	return ns ? div64_u64((u64)bytes * 1000, ns) : 0;	/* bytes/ns*1000 = MB/s */
}

/* Retorna 0 = PASS, 1 = inconclusivo, <0 = FAIL. */
static int test_read(struct ctx *c, u32 len)
{
	u32 off = spm_offset;
	u32 con;
	u64 ns_dma = 0, ns_cpu;
	u8 *ref, *ref2;
	ktime_t t0;
	size_t i;
	int rc, ret;

	if (con_for((u32)(spm_base + off) | lower_32_bits(c->dma_b) | len, &con)) {
		dev_err(c->dev, "%u B: alinhamento invalido\n", len);
		return -EINVAL;
	}
	ref = vmalloc(len);
	ref2 = vmalloc(len);
	if (!ref || !ref2) {
		vfree(ref);
		vfree(ref2);
		return -ENOMEM;
	}

	/* 1. referência pela CPU (e vazão do caminho atual) */
	t0 = ktime_get();
	memcpy_fromio(ref, c->spm + off, len);
	ns_cpu = ktime_to_ns(ktime_sub(ktime_get(), t0));

	/* 2. DMA SPM -> B */
	memset(c->b, FILL_B, c->sz + GUARD);
	c->d[0].src = cpu_to_le32((u32)(spm_base + off));
	c->d[0].dst = cpu_to_le32(lower_32_bits(c->dma_b));
	c->d[0].len = cpu_to_le32(len);
	c->d[0].next = 0;
	rc = hw_xfer(c, con, &ns_dma);
	if (rc) {
		dev_err(c->dev, "TESTE read %7u B  FAIL  (hw_xfer rc=%d)\n", len, rc);
		ret = rc;
		goto out;
	}

	/* 4. segunda leitura da CPU, para detectar SPM mudando sozinha */
	memcpy_fromio(ref2, c->spm + off, len);

	/* 3. comparação + guarda */
	ret = 0;
	for (i = len; i < len + GUARD; i++) {
		if (c->b[i] != FILL_B) {
			dev_err(c->dev, "  GUARDA violada: B[%zu]=0x%02x\n", i, c->b[i]);
			ret = -EFAULT;
			goto report;
		}
	}
	for (i = 0; i < len; i++) {
		if (c->b[i] != ref[i]) {
			if (memcmp(ref, ref2, len)) {
				dev_warn(c->dev, "  B[%zu]=0x%02x != CPU 0x%02x, mas a SPM mudou entre as leituras da CPU\n",
					 i, c->b[i], ref[i]);
				ret = 1;
			} else {
				dev_err(c->dev, "  B[%zu]=0x%02x != CPU 0x%02x (SPM estável)\n",
					i, c->b[i], ref[i]);
				ret = -EIO;
			}
			goto report;
		}
	}
	/* Leitura de zeros nos dois lados não prova nada sobre o endereço. */
	if (!memchr_inv(ref, 0, len) && !memchr_inv(c->b, 0, len))
		dev_warn(c->dev, "  aviso: trecho todo 0x00 (igualdade fraca: use um spm_offset com dados)\n");
	if (!memchr_inv(c->b, 0xff, len))
		dev_warn(c->dev, "  aviso: DMA leu tudo 0xff (padrão de leitura sem resposta)\n");
report:
	dev_info(c->dev, "TESTE read %7u B  %s  DMA %llu ns (%llu MB/s) | CPU %llu ns (%llu MB/s)\n",
		 len, ret == 0 ? "PASS " : ret == 1 ? "INCON" : "FAIL ",
		 ns_dma, mbps(len, ns_dma), ns_cpu, mbps(len, ns_cpu));
	print_hex_dump(KERN_INFO, "  spm[0..63] ", DUMP_PREFIX_OFFSET, 16, 1, ref,
		       min_t(u32, len, 64), false);
out:
	vfree(ref);
	vfree(ref2);
	return ret;
}

/*
 * Passo 3: DMA host (A) -> SPM. Retorna 0 = PASS, <0 = FAIL.
 * Verifica pela CPU: o trecho escrito == A, e a guarda de 4 KiB depois dele
 * na SPM não mudou (snapshot antes x depois).
 */
static int test_write(struct ctx *c, u8 *a, dma_addr_t dma_a, u32 len, u32 salt)
{
	u32 off = spm_offset;
	u32 con, i;
	u64 ns_dma = 0, ns_cpu;
	u8 *rb, *g0, *g1;
	ktime_t t0;
	int rc, ret = 0;

	if (con_for(lower_32_bits(dma_a) | (u32)(spm_base + off) | len, &con))
		return -EINVAL;
	rb = vmalloc(len);
	g0 = vmalloc(GUARD);
	g1 = vmalloc(GUARD);
	if (!rb || !g0 || !g1) {
		ret = -ENOMEM;
		goto out;
	}
	for (i = 0; i < len; i++)
		a[i] = (u8)((i * 13 + salt) ^ 0xa5);
	memcpy_fromio(g0, c->spm + off + len, GUARD);

	/* referência de vazão da CPU para escrita no mesmo trecho */
	t0 = ktime_get();
	memcpy_toio(c->spm + off, a, len);
	ns_cpu = ktime_to_ns(ktime_sub(ktime_get(), t0));
	memset_io(c->spm + off, 0, len);	/* zera antes do DMA */

	c->d[0].src = cpu_to_le32(lower_32_bits(dma_a));
	c->d[0].dst = cpu_to_le32((u32)(spm_base + off));
	c->d[0].len = cpu_to_le32(len);
	c->d[0].next = 0;
	rc = hw_xfer(c, con, &ns_dma);
	if (rc) {
		dev_err(c->dev, "TESTE write %7u B  FAIL  (hw_xfer rc=%d)\n", len, rc);
		ret = rc;
		goto out;
	}
	memcpy_fromio(rb, c->spm + off, len);
	memcpy_fromio(g1, c->spm + off + len, GUARD);
	if (memcmp(rb, a, len)) {
		for (i = 0; i < len && rb[i] == a[i]; i++)
			;
		dev_err(c->dev, "  SPM[%u]=0x%02x != escrito 0x%02x\n", i, rb[i], a[i]);
		ret = -EIO;
	} else if (memcmp(g0, g1, GUARD)) {
		dev_err(c->dev, "  GUARDA da SPM alterada depois do trecho escrito\n");
		ret = -EFAULT;
	}
	dev_info(c->dev, "TESTE write %7u B  %s  DMA %llu ns (%llu MB/s) | CPU %llu ns (%llu MB/s)\n",
		 len, ret ? "FAIL " : "PASS ", ns_dma, mbps(len, ns_dma), ns_cpu, mbps(len, ns_cpu));
out:
	vfree(rb);
	vfree(g0);
	vfree(g1);
	return ret;
}

static void run_tests(struct pci_dev *pdev, void __iomem *r)
{
	static const u32 sizes[] = { 256, SZ_4K, SZ_64K, SZ_1M };
	struct device *dev = &pdev->dev;
	struct ctx c = { .dev = dev, .r = r };
	struct pci_dev *spm_pdev;
	resource_size_t spm_start;
	u32 maxb = min_t(u32, maxkb, 1024) * 1024;
	int i, rc;

	if (spm_base != 0x80000000UL && spm_base != 0xC0000000UL) {
		dev_err(dev, "spm_base=0x%lx recusado: so 0x80000000 (H1) ou 0xC0000000 (H2)\n", spm_base);
		return;
	}
	if (write && (spm_base != 0xC0000000UL || spm_offset != WR_OFF || maxb > WR_MAX)) {
		dev_err(dev, "write=1 recusado: exige spm_base=0xC0000000, spm_offset=0x%lx, maxkb<=%u\n",
			WR_OFF, WR_MAX / 1024);
		return;
	}
	if (spm_offset % 64 || spm_offset + maxb > SPM_WINDOW) {
		dev_err(dev, "spm_offset=0x%lx invalido (multiplo de 64 e offset+%u <= 4 MiB)\n",
			spm_offset, maxb);
		return;
	}

	spm_pdev = pci_get_device(SPM_VENDOR, SPM_DEVICE, NULL);
	if (!spm_pdev) {
		dev_err(dev, "SPM 104d:90dd nao encontrada\n");
		return;
	}
	spm_start = pci_resource_start(spm_pdev, 2);
	if (spm_start != SPM_PCI_BAR2 || pci_resource_len(spm_pdev, 2) < SPM_WINDOW) {
		dev_err(dev, "BAR2 da SPM em %pa (esperado 0x80000000); nada armado\n", &spm_start);
		goto put_spm;
	}
	c.spm = ioremap(spm_start, SPM_WINDOW);
	if (!c.spm) {
		dev_err(dev, "ioremap do BAR2 da SPM falhou\n");
		goto put_spm;
	}

	c.sz = maxb;
	if (dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32))) {
		dev_err(dev, "mascara DMA de 32 bits indisponivel\n");
		goto unmap;
	}
	pci_set_master(pdev);
	c.b = dma_alloc_coherent(dev, c.sz + GUARD, &c.dma_b, GFP_KERNEL);
	c.d = dma_alloc_coherent(dev, 4096, &c.dma_d, GFP_KERNEL);
	if (!c.b || !c.d || upper_32_bits(c.dma_b + c.sz + GUARD) || upper_32_bits(c.dma_d)) {
		dev_err(dev, "buffers indisponiveis ou fora de 32 bits; nada armado\n");
		goto free;
	}
	dev_info(dev, "=== DMAC%d le SPM: spm_base=0x%lx (%s) offset=0x%lx | B=%pad desc=%pad ===\n",
		 bar == 0 ? 1 : 2, spm_base, spm_base == SPM_PCI_BAR2 ? "H1" : "H2",
		 spm_offset, &c.dma_b, &c.dma_d);

	if (write) {
		static const u32 wsizes[] = { 256, SZ_4K, SZ_64K };
		dma_addr_t dma_a;
		u8 *a = dma_alloc_coherent(dev, WR_MAX, &dma_a, GFP_KERNEL);

		if (!a || upper_32_bits(dma_a + WR_MAX)) {
			dev_err(dev, "buffer A indisponivel ou fora de 32 bits; nada armado\n");
			if (a)
				dma_free_coherent(dev, WR_MAX, a, dma_a);
			goto free;
		}
		dev_info(dev, "=== DMAC%d ESCREVE na SPM: 0x%lx + 0x%lx | A=%pad ===\n",
			 bar == 0 ? 1 : 2, spm_base, spm_offset, &dma_a);
		for (i = 0; i < ARRAY_SIZE(wsizes) && wsizes[i] <= maxb; i++) {
			rc = test_write(&c, a, dma_a, wsizes[i], 0x60 + i);
			if (rc) {
				c.fail++;
				break;
			}
			c.pass++;
			if (c.leak)
				break;
		}
		/* devolve o trecho a zero (conteúdo original antes dos testes) */
		if (!c.leak)
			memset_io(c.spm + spm_offset, 0, maxb);
		if (c.leak)
			dev_warn(dev, "buffer A MANTIDO (vazamento deliberado)\n");
		else
			dma_free_coherent(dev, WR_MAX, a, dma_a);
		goto summary;
	}

	for (i = 0; i < ARRAY_SIZE(sizes) && sizes[i] <= maxb; i++) {
		rc = test_read(&c, sizes[i]);
		if (rc == 0)
			c.pass++;
		else if (rc == 1)
			c.inconcl++;
		else {
			c.fail++;
			break;		/* para na primeira falha */
		}
		if (c.leak)
			break;
	}
summary:
	dev_info(dev, "RESUMO: %d PASS, %d INCONCLUSIVO, %d FAIL%s\n", c.pass, c.inconcl, c.fail,
		 c.leak ? " (buffers mantidos: controlador pode estar ativo)" : "");
	dump_regs(dev, r, "estado final");
free:
	if (!c.leak) {
		if (c.d)
			dma_free_coherent(dev, 4096, c.d, c.dma_d);
		if (c.b)
			dma_free_coherent(dev, c.sz + GUARD, c.b, c.dma_b);
	} else {
		dev_warn(dev, "buffers MANTIDOS (vazamento deliberado)\n");
	}
unmap:
	iounmap(c.spm);
put_spm:
	pci_dev_put(spm_pdev);
}

static int dmac_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	void __iomem *r;
	int ret;

	if (bar != 0 && bar != 2)
		return -EINVAL;
	ret = pcim_enable_device(pdev);
	if (ret)
		return ret;
	ret = pcim_iomap_regions(pdev, BIT(bar), "baikal_dmac_test_spm");
	if (ret)
		return ret;
	r = pcim_iomap_table(pdev)[bar];
	dev_info(&pdev->dev, "baikal_dmac_test_spm: BAR%d, run=%d spm_base=0x%lx spm_offset=0x%lx maxkb=%u\n",
		 bar, run, spm_base, spm_offset, maxkb);
	dump_regs(&pdev->dev, r, "estado inicial");
	if (run)
		run_tests(pdev, r);
	return 0;
}

static const struct pci_device_id dmac_ids[] = {
	{ PCI_DEVICE(0x104d, 0x90dc) },
	{ }
};
MODULE_DEVICE_TABLE(pci, dmac_ids);

static struct pci_driver dmac_driver = {
	.name = "baikal_dmac_test_spm",
	.id_table = dmac_ids,
	.probe = dmac_probe,
};
module_pci_driver(dmac_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Harness de RE: DMAC Baikal (00:14.5) lendo a SPM (00:14.6 BAR2), somente leitura");
