// SPDX-License-Identifier: GPL-2.0
/*
 * icc_cmd — envia UM comando ICC pelo chardev do driver ps4-bpcie-icc
 * (ioctl ICC_IOCTL_CMD) e imprime a resposta da MCU.
 *
 * Objetivo: Fase 1 do others/docs/PLANO_S5_POWEROFF_ICC.md — testar o S5
 * (major 4, minor 1) com IRQs e LAPIC vivos, fora do pm_power_off.
 *
 * Interface do kernel (drivers/ps4/aeolia-baikal.h e ps4-bpcie-icc.c):
 *   register_chrdev(ICC_MAJOR='I'=73, "icc")  -> sem device_create(): o nó
 *   /dev/icc NÃO é criado pelo udev; esta ferramenta cria /dev/icc (c 73 0)
 *   se ele não existir.
 *   struct icc_cmd { u8 major; u16 minor; void *data; u16 length;
 *                    void *reply; u16 reply_length; };
 *   Retorno do ioctl: >=0 = bytes de payload da resposta; <0 = -errno
 *   (-ETIMEDOUT, -EIO = checksum/major/minor errados, etc).
 *
 * Uso:
 *   icc_cmd selftest                   # 2/6 = versão do FW (o driver faz isso no boot)
 *   icc_cmd s5 --yes                   # 4/1 {0,0,2,0,1,0}: DESLIGA o console (S5)
 *   icc_cmd raw <major> <minor> [hex] [--reply N] --yes
 *
 * Salvaguardas:
 *   - um único comando por execução; sem laços, sem varredura (AGENTS.md:
 *     "NUNCA varrer ICC minors com data=1");
 *   - qualquer comando além do selftest exige --yes;
 *   - "s5" faz sync() antes e avisa para remontar o / como ro.
 */
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

struct icc_cmd {
	uint8_t major;
	uint16_t minor;
	void *data;
	uint16_t length;
	void *reply;
	uint16_t reply_length;
};

/* Layout tem que bater com o do kernel x86_64 (alinhamento natural). */
_Static_assert(offsetof(struct icc_cmd, minor) == 2, "minor");
_Static_assert(offsetof(struct icc_cmd, data) == 8, "data");
_Static_assert(offsetof(struct icc_cmd, length) == 16, "length");
_Static_assert(offsetof(struct icc_cmd, reply) == 24, "reply");
_Static_assert(offsetof(struct icc_cmd, reply_length) == 32, "reply_length");
_Static_assert(sizeof(struct icc_cmd) == 40, "sizeof");

#define ICC_MAJOR_NUM	'I'
#define ICC_IOCTL_CMD	_IOWR(ICC_MAJOR_NUM, 1, struct icc_cmd)
#define ICC_DEV		"/dev/icc"
#define ICC_MAX_PAYLOAD	(0x7f0 - 0x0c)
#define DEFAULT_REPLY	0x30

static void usage(void)
{
	fprintf(stderr,
		"uso:\n"
		"  icc_cmd selftest\n"
		"  icc_cmd s5 --yes\n"
		"  icc_cmd raw <major> <minor> [payload_hex] [--reply N] --yes\n"
		"exemplo raw: icc_cmd raw 4 1 000002000100 --yes\n");
	exit(2);
}

static int open_icc(void)
{
	struct stat st;
	int fd;

	if (stat(ICC_DEV, &st) != 0) {
		if (mknod(ICC_DEV, S_IFCHR | 0600, makedev(ICC_MAJOR_NUM, 0)) != 0) {
			fprintf(stderr, "mknod %s (c %d 0): %s\n", ICC_DEV,
				ICC_MAJOR_NUM, strerror(errno));
			return -1;
		}
		printf("criado %s (c %d 0)\n", ICC_DEV, ICC_MAJOR_NUM);
	} else if (!S_ISCHR(st.st_mode) || major(st.st_rdev) != ICC_MAJOR_NUM) {
		fprintf(stderr, "%s existe mas não é o chardev %d:0\n", ICC_DEV,
			ICC_MAJOR_NUM);
		return -1;
	}
	fd = open(ICC_DEV, O_RDWR);
	if (fd < 0)
		fprintf(stderr, "open %s: %s\n", ICC_DEV, strerror(errno));
	return fd;
}

static int parse_hex(const char *s, uint8_t *out, size_t max)
{
	size_t n = strlen(s), i;

	if (n % 2 || n / 2 > max)
		return -1;
	for (i = 0; i < n / 2; i++) {
		unsigned int b;

		if (!isxdigit((unsigned char)s[2 * i]) ||
		    !isxdigit((unsigned char)s[2 * i + 1]) ||
		    sscanf(s + 2 * i, "%2x", &b) != 1)
			return -1;
		out[i] = (uint8_t)b;
	}
	return (int)(n / 2);
}

static void hexdump(const char *tag, const uint8_t *b, int n)
{
	int i;

	printf("%s (%d bytes):", tag, n);
	for (i = 0; i < n; i++)
		printf("%s%02x", (i % 16) ? " " : "\n  ", b[i]);
	printf("\n");
}

static int send_cmd(uint8_t maj, uint16_t min, uint8_t *data, int len, int rlen)
{
	static uint8_t reply[0x800];
	struct icc_cmd c = {
		.major = maj, .minor = min,
		.data = data, .length = (uint16_t)len,
		.reply = reply, .reply_length = (uint16_t)rlen,
	};
	int fd, ret;

	fd = open_icc();
	if (fd < 0)
		return 1;
	printf("ICC -> major=%u minor=0x%x\n", maj, min);
	hexdump("payload", data, len);
	fflush(stdout);
	ret = ioctl(fd, ICC_IOCTL_CMD, &c);
	if (ret < 0) {
		printf("ioctl falhou: %s (errno %d)\n", strerror(errno), errno);
		close(fd);
		return 1;
	}
	printf("ioctl ok: MCU respondeu %d bytes de payload\n", ret);
	hexdump("reply", reply, ret < rlen ? ret : rlen);
	close(fd);
	return 0;
}

int main(int argc, char **argv)
{
	uint8_t buf[ICC_MAX_PAYLOAD];
	int yes = 0, rlen = DEFAULT_REPLY, i, n = 0;

	if (argc < 2)
		usage();
	for (i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "--yes"))
			yes = 1;
		else if (!strcmp(argv[i], "--reply") && i + 1 < argc)
			rlen = atoi(argv[++i]);
	}
	if (rlen < 0 || rlen > 0x7e4)
		usage();

	if (!strcmp(argv[1], "selftest"))
		return send_cmd(2, 6, buf, 0, DEFAULT_REPLY);

	if (!yes) {
		fprintf(stderr, "recusado: comando diferente de selftest exige --yes\n");
		return 2;
	}

	if (!strcmp(argv[1], "s5")) {
		/* Mesmo payload do icc_shutdown original (fail0verflow). */
		static const uint8_t s5[] = { 0, 0, 2, 0, 1, 0 };

		memcpy(buf, s5, sizeof(s5));
		printf("S5: o console deve DESLIGAR. Recomendado antes: "
		       "mount -o remount,ro /\n");
		sync();
		return send_cmd(4, 1, buf, sizeof(s5), DEFAULT_REPLY);
	}

	if (!strcmp(argv[1], "raw") && argc >= 4) {
		long maj = strtol(argv[2], NULL, 0), min = strtol(argv[3], NULL, 0);

		if (maj < 0 || maj > 0xff || min < 0 || min > 0xffff)
			usage();
		if (argc >= 5 && argv[4][0] != '-') {
			n = parse_hex(argv[4], buf, sizeof(buf));
			if (n < 0) {
				fprintf(stderr, "payload hex inválido\n");
				return 2;
			}
		}
		return send_cmd((uint8_t)maj, (uint16_t)min, buf, n, rlen);
	}
	usage();
	return 2;
}
