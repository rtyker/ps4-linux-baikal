// SPDX-License-Identifier: GPL-2.0
/*
 * aeolia_dmac_test — Harness de RE para o Aeolia DMAC (00:14.7, 104d:90ce/90a3).
 * O Aeolia DMAC é o motor DMA integrado no device composto xHCI+AHCI,
 * usado pelo Orbis para DDR3 swap via aeolia_dmac_xfer_upstream().
 *
 * Diferente do DMAC standalone (00:14.5, 104d:90dc), o Aeolia DMAC
 * tem registradores próprios nos BARs do device 00:14.7.
 *
 * Objetivo (Passo 2 revisado do PLANO_DMA_SPM_DDR3_2026-11-16.md):
 * - Testar se o Aeolia DMAC consegue ter o BAR2 da SPM (00:14.6, 0x80000000) como origem/destino
 * - Modo src_spm=1: descritor com origem = 0x80000000 + off, destino = buffer coerente do host
 * - Tamanhos crescentes: 256 B → 4 KiB → 64 KiB → 1 MiB, dentro dos primeiros 4 MiB
 * - Comparar byte a byte com leitura CPU do mesmo trecho (via baikal-memory)
 *
 * Pré-condições:
 * - rmmod xhci_aeolia ahci ANTES (disputam o 00:14.7) — CUIDADO: derruba USB/SATA!
 * - Usar o device 00:14.7 (PCI ID 104d:90ce ou 104d:90a3)
 * - Parar na primeira falha
 * - Salvaguardas: controlador ocioso, buffers mantidos se erro, reset se disponível
 *
 * Candidatos de endereço para a SPM no Aeolia DMAC:
 * H1: 0x80000000 + off  (janela PCI do BAR2 da SPM)
 * H2: 0xC0000000 + off  (endereço interno citado no writeup Belize)
 * H3: Endereço interno do Aeolia (descoberto via RE do aeolia_dmac_xfer_upstream)
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

/* Registradores do Aeolia DMAC — OFFSETS A CONFIRMAR VIA RE */
/* Baseado no DMAC standalone (00:14.5) mas podem ser diferentes */
#define AEOLIA_DMAC_UNK70     0x70
#define AEOLIA_DMAC_INT_FLAG  0x80
#define AEOLIA_DMAC_INT       0x84
#define AEOLIA_DMAC_EN        0x88
#define AEOLIA_DMAC_RST       0x8c
#define AEOLIA_DMAC_DESC_ADDR 0x90
#define AEOLIA_DMAC_UNK94     0x94
#define AEOLIA_DMAC_CON       0x98
#define AEOLIA_DMAC_SRC       0x9c
#define AEOLIA_DMAC_DST       0xa0
#define AEOLIA_DMAC_LEN       0xa4
#define AEOLIA_DMAC_DESC_EN   0xa8
#define AEOLIA_DMAC_DEBUG_ST  0xac

/* Parâmetros do módulo */
static int run;
module_param(run, int, 0444);
static int bar;
module_param(bar, int, 0444);  /* Qual BAR do Aeolia (provavelmente 0 ou 2) */
static unsigned int tests = 1;
module_param(tests, uint, 0444);
static unsigned int bigkb = 64;
module_param(bigkb, uint, 0444);
static int inten;
module_param(inten, int, 0444);
static int irqmode;
module_param(irqmode, int, 0444);
static int nvec = 1;
module_param(nvec, int, 0444);

/* NOVO: modo SPM — origem/destino no BAR2 da SPM (0x80000000) */
static int src_spm;
module_param(src_spm, int, 0444);
static int dst_spm;
module_param(dst_spm, int, 0444);

/* NOVO: endereço base candidato para a SPM no Aeolia DMAC */
static unsigned long spm_base = 0x80000000UL;  /* H1: janela PCI BAR2 SPM */
module_param(spm_base, ulong, 0444);

/* NOVO: offset dentro da janela (deve ser < 4 MiB = 0x400000) */
static unsigned long spm_offset;
module_param(spm_offset, ulong, 0444);

/* Device IDs do Aeolia */
#define AEOLIA_VENDOR_ID  0x104d
#define AEOLIA_DEVICE_ID1 0x90ce  /* Aeolia DMA1? */
#define AEOLIA_DEVICE_ID2 0x90a3  /* Aeolia DMA2? */

#define GUARD 4096

struct aeolia_dmac_desc {
	__le32 src;
	__le32 dst;
	__le32 len;
	__le32 next;
};

struct ctx {
	struct device *dev;
	void __iomem *r;
	bool leak;
	u8 *a, *b;
	dma_addr_t dma_a, dma_b;
	size_t sz;
	struct aeolia_dmac_desc *d;
	dma_addr_t dma_d;
	int pass, fail;

	/* interrupção */
	bool irq_ok;
	int irq;
	int irqs[2];
	int nirq;
	unsigned int hits[2];
	struct completion done;
	u32 irq_flag;
	unsigned int irq_count, irq_missed;
};

static irqreturn_t aeolia_dmac_irq(int irq, void *data)
{
	struct ctx *c = data;
	u32 f;

	if (c->nirq > 1 && irq == c->irqs[1])
		c->hits[1]++;
	else
		c->hits[0]++;
	f = readl(c->r + AEOLIA_DMAC_INT_FLAG);
	if (!(f & 0x1f))
		return IRQ_NONE;
	c->irq_flag = f;
	c->irq_count++;
	writel(f & ~0x1u, c->r + AEOLIA_DMAC_INT_FLAG);
	complete(&c->done);
	return IRQ_HANDLED;
}

static void dump_regs(struct device *dev, void __iomem *r, const char *tag)
{
	static const u32 offs[] = { AEOLIA_DMAC_UNK70, AEOLIA_DMAC_INT_FLAG, AEOLIA_DMAC_INT, AEOLIA_DMAC_EN,
		AEOLIA_DMAC_RST, AEOLIA_DMAC_DESC_ADDR, AEOLIA_DMAC_UNK94, AEOLIA_DMAC_CON, AEOLIA_DMAC_SRC,
		AEOLIA_DMAC_DST, AEOLIA_DMAC_LEN, AEOLIA_DMAC_DESC_EN, AEOLIA_DMAC_DEBUG_ST };
	int i;

	dev_info(dev, "%s:", tag);
	for (i = 0; i < ARRAY_SIZE(offs); i++)
		dev_info(dev, "  +0x%02x = 0x%08x", offs[i], readl(r + offs[i]));
}

/* CON conforme a tabela do Orbis DMAC standalone (pode ser igual no Aeolia) */
static int con_for(u32 or_all, u32 *con)
{
	unsigned int tz = __ffs(or_all | 0x80);

	if (tz < 2)
		return -EINVAL;
	*con = tz == 2 ? 0 : tz == 3 ? 0x10000 : tz == 4 ? 0x20000 :
	       tz == 5 ? 0x30000 : 0x40000;
	return 0;
}

static bool spm_offset_valid(unsigned long off)
{
	return off < 0x400000UL;  /* 4 MiB = janela mapeada pelo baikal-memory */
}

static int hw_xfer(struct ctx *c, u32 con, u64 *ns)
{
	void __iomem *r = c->r;
	struct device *dev = c->dev;
	unsigned long to;
	ktime_t t0;
	u32 f = 0;
	bool acked = false;

	if (readl(r + AEOLIA_DMAC_INT_FLAG) || readl(r + AEOLIA_DMAC_INT) || readl(r + AEOLIA_DMAC_DESC_EN) ||
	    readl(r + AEOLIA_DMAC_EN) || readl(r + AEOLIA_DMAC_DESC_ADDR)) {
		dev_err(dev, "controlador NAO ocioso; nada escrito\n");
		return -EBUSY;
	}
	writel(0, r + AEOLIA_DMAC_LEN);
	writel(0, r + AEOLIA_DMAC_SRC);
	writel(0, r + AEOLIA_DMAC_DST);
	if (readl(r + AEOLIA_DMAC_LEN) || readl(r + AEOLIA_DMAC_SRC) || readl(r + AEOLIA_DMAC_DST)) {
		dev_err(dev, "LEN/SRC/DST nao zeraram; abortando antes de armar\n");
		return -EIO;
	}
	writel(lower_32_bits(c->dma_d), r + AEOLIA_DMAC_DESC_ADDR);
	writel(0, r + AEOLIA_DMAC_INT_FLAG);
	writel(con, r + AEOLIA_DMAC_CON);
	writel((inten || c->irq_ok) ? 3 : 0, r + AEOLIA_DMAC_INT);
	if (c->irq_ok) {
		reinit_completion(&c->done);
		c->irq_flag = 0;
	}
	wmb();
	t0 = ktime_get();
	writel(1, r + AEOLIA_DMAC_DESC_EN);

	if (c->irq_ok) {
		if (wait_for_completion_timeout(&c->done, msecs_to_jiffies(2000))) {
			f = c->irq_flag;
			acked = true;
		} else {
			f = readl(r + AEOLIA_DMAC_INT_FLAG);
			if (f & 0x1f) {
				c->irq_missed++;
				dev_warn(dev, "IRQ NAO entregue, mas INT_FLAG=0x%x (so por polling)\n", f);
			}
		}
	} else {
		to = jiffies + msecs_to_jiffies(2000);
		while (time_before(jiffies, to)) {
			f = readl(r + AEOLIA_DMAC_INT_FLAG);
			if (f & 0x1f)
				break;
			cpu_relax();
		}
	}
	*ns = ktime_to_ns(ktime_sub(ktime_get(), t0));
	if (!(f & 0x1f)) {
		dev_err(dev, "TIMEOUT (INT_FLAG=0x%x); reset e buffers mantidos\n", f);
		/* Tentar reset se registrador existir */
		writel(2, r + AEOLIA_DMAC_RST);
		udelay(50);
		writel(0, r + AEOLIA_DMAC_RST);
		c->leak = true;
		return -ETIMEDOUT;
	}
	if (f & 0x1e) {
		dev_err(dev, "ERRO do Aeolia DMAC: INT_FLAG=0x%x DEBUG_ST=0x%x; buffers mantidos\n",
			f, readl(r + AEOLIA_DMAC_DEBUG_ST));
		writel(2, r + AEOLIA_DMAC_RST);
		udelay(50);
		writel(0, r + AEOLIA_DMAC_RST);
		c->leak = true;
		return -EIO;
	}
	if (!acked)
		writel(f & ~0x1u, r + AEOLIA_DMAC_INT_FLAG);
	writel(0, r + AEOLIA_DMAC_INT);
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

static bool verify(struct ctx *c, u32 salt, struct aeolia_dmac_desc *seg, int nseg)
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

static bool verify_against_cpu_read(struct ctx *c, void __iomem *spm_virt, u32 salt,
				    struct aeolia_dmac_desc *seg, int nseg)
{
	size_t i;
	int s;
	bool ok = true;
	u8 *exp = kmalloc(c->sz + GUARD, GFP_KERNEL);
	u8 *cpu_read = kmalloc(c->sz + GUARD, GFP_KERNEL);

	if (!exp || !cpu_read) {
		kfree(exp);
		kfree(cpu_read);
		return false;
	}

	memset(exp, 0xee, c->sz + GUARD);
	for (s = 0; s < nseg; s++) {
		u32 so = le32_to_cpu(seg[s].src) - lower_32_bits(c->dma_a);
		u32 dof = le32_to_cpu(seg[s].dst) - lower_32_bits(c->dma_b);
		u32 l = le32_to_cpu(seg[s].len);

		for (i = 0; i < l; i++)
			exp[dof + i] = (u8)(((so + i) * 7 + salt) ^ 0x5a);
	}

	for (s = 0; s < nseg; s++) {
		u32 spm_phys = le32_to_cpu(seg[s].src);
		u32 dof = le32_to_cpu(seg[s].dst) - lower_32_bits(c->dma_b);
		u32 l = le32_to_cpu(seg[s].len);
		void __iomem *spm_src = spm_virt + (spm_phys - spm_base);

		memcpy_fromio(cpu_read + dof, spm_src, l);
	}

	for (i = 0; i < c->sz + GUARD; i++) {
		if (c->b[i] != cpu_read[i]) {
			dev_err(c->dev, "  DMAC B[%zu]=0x%02x != CPU read 0x%02x%s\n", i, c->b[i], cpu_read[i],
				i >= c->sz ? " (GUARDA violada!)" : "");
			ok = false;
			break;
		}
		if (c->b[i] != exp[i]) {
			dev_err(c->dev, "  B[%zu]=0x%02x != expected 0x%02x\n", i, c->b[i], exp[i]);
			ok = false;
			break;
		}
	}

	kfree(exp);
	kfree(cpu_read);
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

static int single_desc_spm(struct ctx *c, void __iomem *spm_virt, u32 spm_off,
			   u32 host_off, u32 len, u32 salt,
			   const char *name, u32 *con_out)
{
	u32 con;
	u64 ns = 0;
	int rc;
	bool ok;

	if (!spm_offset_valid(spm_off)) {
		dev_err(c->dev, "%s: spm_offset 0x%x fora da janela 4 MiB\n", name, spm_off);
		c->fail++;
		return -EINVAL;
	}

	if (con_for(lower_32_bits(c->dma_a + host_off) | spm_base + spm_off | len, &con)) {
		dev_err(c->dev, "%s: alinhamento invalido\n", name);
		c->fail++;
		return -EINVAL;
	}

	fill(c, salt);

	if (src_spm) {
		c->d[0].src = cpu_to_le32(spm_base + spm_off);
		c->d[0].dst = cpu_to_le32(lower_32_bits(c->dma_b + host_off));
	} else if (dst_spm) {
		c->d[0].src = cpu_to_le32(lower_32_bits(c->dma_a + host_off));
		c->d[0].dst = cpu_to_le32(spm_base + spm_off);
	} else {
		dev_err(c->dev, "%s: nem src_spm nem dst_spm habilitado\n", name);
		c->fail++;
		return -EINVAL;
	}
	c->d[0].len = cpu_to_le32(len);
	c->d[0].next = 0;

	rc = hw_xfer(c, con, &ns);

	if (src_spm) {
		ok = rc ? false : verify_against_cpu_read(c, spm_virt, salt, c->d, 1);
	} else {
		if (rc == 0) {
			u8 *cpu_read = kmalloc(len, GFP_KERNEL);
			if (cpu_read) {
				void __iomem *spm_dst = spm_virt + spm_off;
				memcpy_fromio(cpu_read, spm_dst, len);
				ok = true;
				for (i = 0; i < len; i++) {
					u8 expected = (u8)((i * 7 + salt) ^ 0x5a);
					if (cpu_read[i] != expected) {
						dev_err(c->dev, "  SPM write readback[%u]=0x%02x expected 0x%02x\n",
							i, cpu_read[i], expected);
						ok = false;
						break;
					}
				}
				kfree(cpu_read);
			} else {
				ok = false;
			}
		} else {
			ok = false;
		}
	}

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

	/* Mapear a SPM BAR2 (0x80000000) para readback CPU */
	void __iomem *spm_virt = NULL;
	resource_size_t spm_phys = 0x80000000ULL;

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
				if (request_irq(c.irqs[k], aeolia_dmac_irq, IRQF_SHARED, "aeolia_dmac_test", &c))
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
			dev_err(dev, "modo IRQ indisponivel; abortando sem armar o Aeolia DMAC\n");
			dma_free_coherent(dev, 4096, c.d, c.dma_d);
			dma_free_coherent(dev, c.sz + GUARD, c.b, c.dma_b);
			dma_free_coherent(dev, c.sz + GUARD, c.a, c.dma_a);
			return;
		}
	}

	/* Testes SPM (src_spm ou dst_spm) */
	if (src_spm || dst_spm) {
		dev_info(dev, "=== TESTES SPM via Aeolia DMAC (src_spm=%d dst_spm=%d spm_base=0x%lx spm_offset=0x%lx) ===\n",
			 src_spm, dst_spm, spm_base, spm_offset);

		if (tests & 1) {
			char nm[40];
			snprintf(nm, sizeof(nm), "SPM %s 256B", src_spm ? "read" : "write");
			single_desc_spm(&c, spm_virt, spm_offset, 0, 256, 0x11, nm, NULL);
		}

		if ((tests & 4) && !c.leak) {
			char nm[40];
			snprintf(nm, sizeof(nm), "SPM %s %zu KiB", src_spm ? "read" : "write", c.sz / 1024);
			single_desc_spm(&c, spm_virt, spm_offset, 0, c.sz, 0x33, nm, NULL);
		}

		if ((tests & 8) && !c.leak) {
			static const unsigned int tz[] = { 2, 3, 4, 5, 6 };
			char nm[40];

			for (i = 0; i < ARRAY_SIZE(tz) && !c.leak; i++) {
				u32 unit = 1u << tz[i];
				u32 off = spm_offset + unit;

				if (!spm_offset_valid(off))
					break;

				snprintf(nm, sizeof(nm), "SPM %s alinh %u B", src_spm ? "read" : "write", unit);
				single_desc_spm(&c, spm_virt, off, unit, unit * 3, 0x44 + i, nm, NULL);
			}
		}
	} else {
		/* Testes host-to-host (para validar Aeolia DMAC básico) */
		dev_info(dev, "=== TESTES HOST-TO-HOST (validacao basica do Aeolia DMAC) ===\n");
		
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
				single_desc(&c, unit, unit, unit * 3, 0x44 + i, nm, NULL);
			}
		}
	}

	if (c.irq_ok) {
		int k;

		writel(0, r + AEOLIA_DMAC_INT);
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

/* single_desc para host-to-host (copiado do baikal_dmac_test.c) */
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

static int aeolia_dmac_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	void __iomem *r;
	int ret;

	if (bar != 0 && bar != 2)
		return -EINVAL;
	ret = pcim_enable_device(pdev);
	if (ret)
		return ret;
	ret = pcim_iomap_regions(pdev, BIT(bar), "aeolia_dmac_test");
	if (ret)
		return ret;
	r = pcim_iomap_table(pdev)[bar];
	dev_info(&pdev->dev, "aeolia_dmac_test: BAR%d mapeado, run=%d tests=0x%x src_spm=%d dst_spm=%d spm_base=0x%lx\n",
		 bar, run, tests, src_spm, dst_spm, spm_base);
	dump_regs(&pdev->dev, r, "estado inicial");
	if (run)
		run_tests(pdev, r);
	return 0;
}

static const struct pci_device_id aeolia_dmac_ids[] = {
	{ PCI_DEVICE(AEOLIA_VENDOR_ID, AEOLIA_DEVICE_ID1) },
	{ PCI_DEVICE(AEOLIA_VENDOR_ID, AEOLIA_DEVICE_ID2) },
	{ }
};
MODULE_DEVICE_TABLE(pci, aeolia_dmac_ids);

static struct pci_driver aeolia_dmac_driver = {
	.name = "aeolia_dmac_test",
	.id_table = aeolia_dmac_ids,
	.probe = aeolia_dmac_probe,
};
module_pci_driver(aeolia_dmac_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Harness de RE do Aeolia DMAC (00:14.7) para SPM/DDR3");