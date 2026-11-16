// SPDX-License-Identifier: GPL-2.0
/*
 * baikal_dmac_test — harness de RE para o DMAC do Baikal (00:14.5, 104d:90dc).
 * NAO e driver definitivo. Valida, com buffers proprios, a sequencia de
 * transferencia decodificada do dmac_mtk.c do Orbis
 * (outros/rea/dma/decompiled/baikal_dmac_mtk_registers_20261113.md).
 *
 * Parametros:
 *   run=0     so le e imprime os registradores (padrao).
 *   run=1     executa os testes selecionados por 'tests'.
 *   bar=0|2   qual controlador.
 *   tests=M   mascara: 1=simples(256B) 2=encadeamento(3 desc) 4=grande
 *             8=alinhamentos (CON). Padrao 1.
 *   bigkb=N   tamanho do teste grande em KiB (4..1024, padrao 64).
 *   inten=1   grava INT=3 como o Orbis (padrao 0: sem interrupcao, polling).
 *
 * Salvaguardas: so opera com o controlador ocioso; zera LEN/SRC/DST como o
 * Orbis e CONFERE a releitura; so usa buffers coerentes proprios (com margem
 * de guarda conferida); se uma transferencia nao terminar, NAO libera os
 * buffers (o DMA nunca pode escrever em memoria reaproveitada).
 */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/interrupt.h>
#include <linux/completion.h>
#include <asm/ps4.h>

#define DMAC_UNK70	0x70
#define DMAC_INT_FLAG	0x80
#define DMAC_INT	0x84
#define DMAC_EN		0x88
#define DMAC_RST	0x8c
#define DMAC_DESC_ADDR	0x90
#define DMAC_UNK94	0x94
#define DMAC_CON	0x98
#define DMAC_SRC	0x9c
#define DMAC_DST	0xa0
#define DMAC_LEN	0xa4
#define DMAC_DESC_EN	0xa8
#define DMAC_DEBUG_ST	0xac

static int run;
module_param(run, int, 0444);
static int bar;
module_param(bar, int, 0444);
static unsigned int tests = 1;
module_param(tests, uint, 0444);
static unsigned int bigkb = 64;
module_param(bigkb, uint, 0444);
static int inten;
module_param(inten, int, 0444);
/* irqmode=1: usa interrupcao real (MSI via bpcie_assign_irqs) em vez de polling */
static int irqmode;
module_param(irqmode, int, 0444);
/* nvec=2: pede 2 vetores MSI direto (pci_alloc_irq_vectors); irqvec: qual deles usar */
static int nvec = 1;
module_param(nvec, int, 0444);

struct dmac_desc {		/* 16 bytes; layout do Orbis, confirmado ao vivo */
	__le32 src;		/* +0x0 origem */
	__le32 dst;		/* +0x4 destino */
	__le32 len;		/* +0x8 comprimento */
	__le32 next;		/* +0xc proximo descritor, 0 = fim */
};

#define GUARD 4096
struct ctx {
	struct device *dev;
	void __iomem *r;
	bool leak;		/* controlador pode estar ativo: nao liberar */
	u8 *a, *b;
	dma_addr_t dma_a, dma_b;
	size_t sz;		/* tamanho util; cada buffer tem sz + GUARD */
	struct dmac_desc *d;
	dma_addr_t dma_d;
	int pass, fail;
	/* interrupcao */
	bool irq_ok;		/* handlers registrados e em uso */
	int irq;
	int irqs[2];
	int nirq;
	unsigned int hits[2];	/* chamadas do handler por vetor (mesmo sem INT_FLAG) */
	struct completion done;
	u32 irq_flag;
	unsigned int irq_count, irq_missed;
};

static irqreturn_t dmac_irq(int irq, void *data)
{
	struct ctx *c = data;
	u32 f;

	if (c->nirq > 1 && irq == c->irqs[1])
		c->hits[1]++;
	else
		c->hits[0]++;
	f = readl(c->r + DMAC_INT_FLAG);
	if (!(f & 0x1f))
		return IRQ_NONE;
	c->irq_flag = f;
	c->irq_count++;
	writel(f & ~0x1u, c->r + DMAC_INT_FLAG);	/* ack igual ao ISR do Orbis */
	complete(&c->done);
	return IRQ_HANDLED;
}

static void dump_regs(struct device *dev, void __iomem *r, const char *tag)
{
	static const u32 offs[] = { DMAC_UNK70, DMAC_INT_FLAG, DMAC_INT, DMAC_EN,
		DMAC_RST, DMAC_DESC_ADDR, DMAC_UNK94, DMAC_CON, DMAC_SRC,
		DMAC_DST, DMAC_LEN, DMAC_DESC_EN, DMAC_DEBUG_ST };
	int i;

	dev_info(dev, "%s:", tag);
	for (i = 0; i < ARRAY_SIZE(offs); i++)
		dev_info(dev, "  +0x%02x = 0x%08x", offs[i], readl(r + offs[i]));
}

/* CON conforme a tabela do Orbis: depende do alinhamento minimo (tzcnt). */
static int con_for(u32 or_all, u32 *con)
{
	unsigned int tz = __ffs(or_all | 0x80);

	if (tz < 2)
		return -EINVAL;
	*con = tz == 2 ? 0 : tz == 3 ? 0x10000 : tz == 4 ? 0x20000 :
	       tz == 5 ? 0x30000 : 0x40000;
	return 0;
}

static int hw_xfer(struct ctx *c, u32 con, u64 *ns)
{
	void __iomem *r = c->r;
	struct device *dev = c->dev;
	unsigned long to;
	ktime_t t0;
	u32 f = 0;
	bool acked = false;

	if (readl(r + DMAC_INT_FLAG) || readl(r + DMAC_INT) || readl(r + DMAC_DESC_EN) ||
	    readl(r + DMAC_EN) || readl(r + DMAC_DESC_ADDR)) {
		dev_err(dev, "controlador NAO ocioso; nada escrito\n");
		return -EBUSY;
	}
	writel(0, r + DMAC_LEN);
	writel(0, r + DMAC_SRC);
	writel(0, r + DMAC_DST);
	if (readl(r + DMAC_LEN) || readl(r + DMAC_SRC) || readl(r + DMAC_DST)) {
		dev_err(dev, "LEN/SRC/DST nao zeraram; abortando antes de armar\n");
		return -EIO;
	}
	writel(lower_32_bits(c->dma_d), r + DMAC_DESC_ADDR);
	writel(0, r + DMAC_INT_FLAG);
	writel(con, r + DMAC_CON);
	writel((inten || c->irq_ok) ? 3 : 0, r + DMAC_INT);
	if (c->irq_ok) {
		reinit_completion(&c->done);
		c->irq_flag = 0;
	}
	wmb();
	t0 = ktime_get();
	writel(1, r + DMAC_DESC_EN);

	if (c->irq_ok) {
		if (wait_for_completion_timeout(&c->done, msecs_to_jiffies(2000))) {
			f = c->irq_flag;
			acked = true;
		} else {
			f = readl(r + DMAC_INT_FLAG);
			if (f & 0x1f) {
				c->irq_missed++;
				dev_warn(dev, "IRQ NAO entregue, mas INT_FLAG=0x%x (so por polling)\n", f);
			}
		}
	} else {
		to = jiffies + msecs_to_jiffies(2000);
		while (time_before(jiffies, to)) {
			f = readl(r + DMAC_INT_FLAG);
			if (f & 0x1f)
				break;
			cpu_relax();
		}
	}
	*ns = ktime_to_ns(ktime_sub(ktime_get(), t0));
	if (!(f & 0x1f)) {
		dev_err(dev, "TIMEOUT (INT_FLAG=0x%x); reset e buffers mantidos\n", f);
		writel(2, r + DMAC_RST);
		udelay(50);
		writel(0, r + DMAC_RST);
		c->leak = true;
		return -ETIMEDOUT;
	}
	if (f & 0x1e) {
		dev_err(dev, "ERRO do DMAC: INT_FLAG=0x%x DEBUG_ST=0x%x; buffers mantidos\n",
			f, readl(r + DMAC_DEBUG_ST));
		writel(2, r + DMAC_RST);
		udelay(50);
		writel(0, r + DMAC_RST);
		c->leak = true;
		return -EIO;
	}
	if (!acked)
		writel(f & ~0x1u, r + DMAC_INT_FLAG);
	writel(0, r + DMAC_INT);
	return 0;
}

static void fill(struct ctx *c, u32 salt)
{
	size_t i;

	for (i = 0; i < c->sz + GUARD; i++) {
		c->a[i] = (u8)((i * 7 + salt) ^ 0x5a);
		c->b[i] = 0xee;
	}
}

/* Confere: [do,do+len) de B == [so,so+len) de A; fora disso B segue 0xee; A intacto. */
static bool verify(struct ctx *c, u32 salt, struct dmac_desc *seg, int nseg)
{
	size_t i;
	int s;
	bool ok = true;
	u8 *exp = kmalloc(c->sz + GUARD, GFP_KERNEL);

	if (!exp)
		return false;
	memset(exp, 0xee, c->sz + GUARD);
	for (s = 0; s < nseg; s++) {
		u32 so = le32_to_cpu(seg[s].src) - lower_32_bits(c->dma_a);
		u32 dof = le32_to_cpu(seg[s].dst) - lower_32_bits(c->dma_b);
		u32 l = le32_to_cpu(seg[s].len);

		for (i = 0; i < l; i++)
			exp[dof + i] = (u8)(((so + i) * 7 + salt) ^ 0x5a);
	}
	for (i = 0; i < c->sz + GUARD; i++) {
		if (c->b[i] != exp[i]) {
			dev_err(c->dev, "  B[%zu]=0x%02x esperado 0x%02x%s\n", i, c->b[i], exp[i],
				i >= c->sz ? " (GUARDA violada!)" : "");
			ok = false;
			break;
		}
		if (c->a[i] != (u8)((i * 7 + salt) ^ 0x5a)) {
			dev_err(c->dev, "  A[%zu] foi alterado\n", i);
			ok = false;
			break;
		}
	}
	kfree(exp);
	return ok;
}

static void result(struct ctx *c, const char *name, int rc, bool ok, u64 ns, size_t bytes)
{
	if (rc == 0 && ok) {
		c->pass++;
		dev_info(c->dev, "TESTE %-28s PASS  (%llu ns, %zu B)\n", name, ns, bytes);
	} else {
		c->fail++;
		dev_err(c->dev, "TESTE %-28s FAIL  (rc=%d ok=%d)\n", name, rc, ok);
	}
}

static int single_desc(struct ctx *c, u32 so, u32 dof, u32 len, u32 salt,
		       const char *name, u32 *con_out)
{
	u32 con;
	u64 ns = 0;
	int rc;
	bool ok;

	if (con_for(lower_32_bits(c->dma_a + so) | lower_32_bits(c->dma_b + dof) | len, &con)) {
		dev_err(c->dev, "%s: alinhamento invalido\n", name);
		c->fail++;
		return -EINVAL;
	}
	fill(c, salt);
	c->d[0].src = cpu_to_le32(lower_32_bits(c->dma_a + so));
	c->d[0].dst = cpu_to_le32(lower_32_bits(c->dma_b + dof));
	c->d[0].len = cpu_to_le32(len);
	c->d[0].next = 0;
	rc = hw_xfer(c, con, &ns);
	ok = rc ? false : verify(c, salt, c->d, 1);
	if (con_out)
		*con_out = con;
	result(c, name, rc, ok, ns, len);
	return rc;
}

static void run_tests(struct pci_dev *pdev, void __iomem *r)
{
	struct device *dev = &pdev->dev;
	struct ctx c = { .dev = dev, .r = r };
	size_t big = (size_t)clamp(bigkb, 4u, 1024u) * 1024;
	int i;

	c.sz = big;
	if (dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32))) {
		dev_err(dev, "mascara DMA de 32 bits indisponivel\n");
		return;
	}
	pci_set_master(pdev);
	c.a = dma_alloc_coherent(dev, c.sz + GUARD, &c.dma_a, GFP_KERNEL);
	c.b = dma_alloc_coherent(dev, c.sz + GUARD, &c.dma_b, GFP_KERNEL);
	c.d = dma_alloc_coherent(dev, 4096, &c.dma_d, GFP_KERNEL);
	if (!c.a || !c.b || !c.d) {
		dev_err(dev, "falha ao alocar buffers (nada programado)\n");
		return;
	}
	if (upper_32_bits(c.dma_a + c.sz + GUARD) || upper_32_bits(c.dma_b + c.sz + GUARD) ||
	    upper_32_bits(c.dma_d)) {
		dev_err(dev, "buffers fora de 32 bits; abortando\n");
		return;
	}
	dev_info(dev, "buffers: A=%pad B=%pad desc=%pad util=%zu B (+%d guarda)\n",
		 &c.dma_a, &c.dma_b, &c.dma_d, c.sz, GUARD);

	init_completion(&c.done);
	if (irqmode) {
		int n = nvec > 1 ? pci_alloc_irq_vectors(pdev, nvec, nvec, PCI_IRQ_MSI)
				 : bpcie_assign_irqs(pdev, 1);

		if (n <= 0) {
			dev_err(dev, "alocacao de IRQ falhou: n=%d\n", n);
		} else {
			int k, ok = 0;

			c.nirq = min(n, 2);
			for (k = 0; k < c.nirq; k++) {
				c.irqs[k] = nvec > 1 ? pci_irq_vector(pdev, k) : pdev->irq;
				if (request_irq(c.irqs[k], dmac_irq, IRQF_SHARED, "baikal_dmac_test", &c))
					break;
				ok++;
			}
			if (ok != c.nirq) {
				dev_err(dev, "request_irq falhou no vetor %d\n", ok);
				while (ok--)
					free_irq(c.irqs[ok], &c);
				pci_free_irq_vectors(pdev);
			} else {
				c.irq = c.irqs[0];
				c.irq_ok = true;
				dev_info(dev, "IRQs registradas: %d%s%d (vetores=%d)\n", c.irqs[0],
					 c.nirq > 1 ? " e " : " / -", c.nirq > 1 ? c.irqs[1] : 0, n);
			}
		}
		if (!c.irq_ok) {
			dev_err(dev, "modo IRQ indisponivel; abortando sem armar o DMAC\n");
			dma_free_coherent(dev, 4096, c.d, c.dma_d);
			dma_free_coherent(dev, c.sz + GUARD, c.b, c.dma_b);
			dma_free_coherent(dev, c.sz + GUARD, c.a, c.dma_a);
			return;
		}
	}

	if (tests & 1)
		single_desc(&c, 0, 0, 256, 0x11, "simples 256B", NULL);

	if ((tests & 2) && !c.leak) {
		static const u32 so[3] = { 0, 1024, 4096 };
		static const u32 dof[3] = { 0, 512, 2048 };
		static const u32 ln[3] = { 128, 256, 64 };
		u32 con, orv = 0, salt = 0x22;
		u64 ns = 0;
		int rc;
		bool ok;

		fill(&c, salt);
		for (i = 0; i < 3; i++) {
			c.d[i].src = cpu_to_le32(lower_32_bits(c.dma_a + so[i]));
			c.d[i].dst = cpu_to_le32(lower_32_bits(c.dma_b + dof[i]));
			c.d[i].len = cpu_to_le32(ln[i]);
			c.d[i].next = i == 2 ? 0 : cpu_to_le32(lower_32_bits(c.dma_d + 16 * (i + 1)));
			orv |= lower_32_bits(c.dma_a + so[i]) | lower_32_bits(c.dma_b + dof[i]) | ln[i];
		}
		if (con_for(orv, &con)) {
			c.fail++;
		} else {
			rc = hw_xfer(&c, con, &ns);
			ok = rc ? false : verify(&c, salt, c.d, 3);
			result(&c, "encadeamento 3 descritores", rc, ok, ns, 128 + 256 + 64);
		}
	}

	if ((tests & 4) && !c.leak) {
		char nm[40];
		u32 con = 0;

		snprintf(nm, sizeof(nm), "grande %zu KiB", c.sz / 1024);
		single_desc(&c, 0, 0, c.sz, 0x33, nm, &con);
	}

	if ((tests & 8) && !c.leak) {
		static const unsigned int tz[] = { 2, 3, 4, 5, 6 };
		char nm[40];

		for (i = 0; i < ARRAY_SIZE(tz) && !c.leak; i++) {
			u32 unit = 1u << tz[i];

			snprintf(nm, sizeof(nm), "alinhamento %u B (CON)", unit);
			/* offsets multiplos de 'unit' mas nao do dobro: tzcnt = tz[i] */
			single_desc(&c, unit, unit, unit * 3, 0x44 + i, nm, NULL);
		}
	}

	if (c.irq_ok) {
		int k;

		writel(0, r + DMAC_INT);
		for (k = 0; k < c.nirq; k++)
			free_irq(c.irqs[k], &c);
		pci_free_irq_vectors(pdev);
	}
	dev_info(dev, "RESUMO: %d PASS, %d FAIL%s | irq: entregues=%u perdidas=%u | chamadas vetor0=%u vetor1=%u\n",
		 c.pass, c.fail, c.leak ? " (buffers mantidos: controlador pode estar ativo)" : "",
		 c.irq_count, c.irq_missed, c.hits[0], c.hits[1]);
	dump_regs(dev, r, "estado final");
	if (!c.leak) {
		dma_free_coherent(dev, 4096, c.d, c.dma_d);
		dma_free_coherent(dev, c.sz + GUARD, c.b, c.dma_b);
		dma_free_coherent(dev, c.sz + GUARD, c.a, c.dma_a);
	} else {
		dev_warn(dev, "buffers MANTIDOS (vazamento deliberado)\n");
	}
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
	ret = pcim_iomap_regions(pdev, BIT(bar), "baikal_dmac_test");
	if (ret)
		return ret;
	r = pcim_iomap_table(pdev)[bar];
	dev_info(&pdev->dev, "baikal_dmac_test: BAR%d mapeado, run=%d tests=0x%x\n", bar, run, tests);
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
	.name = "baikal_dmac_test",
	.id_table = dmac_ids,
	.probe = dmac_probe,
};
module_pci_driver(dmac_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Harness de RE do DMAC Baikal (00:14.5)");
