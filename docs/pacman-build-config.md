# Pacman / makepkg Build Configuration

Notes on getting Arch package builds to use all available cores on the Z13
(Strix Halo, 16-core / 32-thread Ryzen AI Max+).

---

## The problem

By default, `makepkg` (used by `pacman`, AUR helpers like `paru`/`yay`, and
DKMS) does **not** automatically use all CPU cores. Without explicit
configuration, builds run single-threaded or with a low default job count,
making kernel module compilation (e.g. `ryzen_smu` DKMS) and AUR package
builds needlessly slow on a 32-thread machine.

---

## The fix — `/etc/makepkg.conf`

The relevant settings in `/etc/makepkg.conf`:

```bash
# Use all cores for compilation
MAKEFLAGS="-j$(nproc)"

# Use all cores for zstd package compression (T0 = all threads)
COMPRESSZST=(zstd -c -T0 -)
```

`$(nproc)` evaluates at build time so it always reflects the actual core count.
On the Z13 this is `32`.

`COMPRESSZST` with `-T0` matters for packages that produce large zst archives —
compression was the bottleneck before this was set.

---

## Full relevant block from `/etc/makepkg.conf`

```bash
CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fno-plt -fexceptions \
        -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security \
        -fstack-clash-protection -fcf-protection \
        -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
         -Wl,-z,pack-relative-relocs"
LTOFLAGS="-flto=auto"

MAKEFLAGS="-j$(nproc)"

COMPRESSZST=(zstd -c -T0 -)
COMPRESSXZ=(xz -c -z -)

PKGEXT='.pkg.tar.zst'
```

Note: `CFLAGS` uses `march=x86-64` (generic baseline) rather than
`march=native`. This is intentional for packages that get cached or shared —
`native` would bake in Strix Halo-specific instructions that could break
compatibility. For personal builds where portability doesn't matter, changing
to `-march=native -mtune=native` would squeeze more performance out.

---

## DKMS specifically

DKMS modules (like `ryzen_smu`) are rebuilt on every kernel update. Without
`MAKEFLAGS`, rebuilding `ryzen_smu` against a new kernel took noticeably longer.
With `-j$(nproc)` the kernel module build is essentially instant.

DKMS reads `MAKEFLAGS` from `/etc/makepkg.conf` when invoked via pacman hooks.

---

## No user-level override needed

There is no `~/.makepkg.conf` — the system-wide `/etc/makepkg.conf` is
sufficient. Any user-level file at `~/.makepkg.conf` would take precedence and
override these settings, so don't create one unless intentionally overriding
specific values.
