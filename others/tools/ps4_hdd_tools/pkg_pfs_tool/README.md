PS4 PKG/PFS tool (c) 2017-2021 by flatz

⚠️ **NOTA IMPORTANTE PARA ESTE PROJETO (PS4 Linux Baikal):**
Esta ferramenta é um **utilitário de HOST** para inspecionar/extrair containers PKG/PFS *no PC*.
O binário que o `CMakeLists.txt` gera é compilado com `-march=native`, ou seja, para a CPU do PC (o `objdump` mostra instruções AVX/ymm); **esse binário não deve ser copiado para o PS4** (o PS4 também é x86_64, mas o Jaguar não tem as mesmas extensões). Para usar no PS4 seria preciso recompilar com `-march=btver2`, e isso nunca foi testado. O foco do nosso projeto é o Linux rodando *no* PS4.
A montagem da partição `sda27` (user data, UFS2) já funciona nativamente no kernel do PS4 (`ufs` driver) — **não precisa desta ferramenta para montar a partição**.
O `pkg_pfs_tool` serve apenas se você quiser abrir/inspecionar os containers `app.pkg`/`.pfs` *dentro* do UFS2 já montado, a partir do seu PC.
Mantido no repo apenas para referência/uso offline; **não é copiado para o rootfs do PS4** pelo build.

---

Dependencies:
* mbedtls
* uthash
* zlib

For ubuntu-ish:
```bash
sudo apt install libmbedtls-dev uthash-dev zlib1g-dev
```

To produce windows executable from ubuntu-ish via mingw:
```bash
sudo apt install mingw-w64 libz-mingw-w64-dev
```
Then pass e.g. `-DCMAKE_TOOLCHAIN_FILE=../cmake/mingw-w64-x86_64.cmake` to cmake.

P.S. In memory of Maxton Garrett (maxton), this release is dedicated to you.
