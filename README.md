# 🐧 Arch Custom ISO

Custom Arch Linux ISO built with `archiso`.

This project allows you to generate a fully customized Arch Linux installation ISO with preconfigured packages, scripts, and system settings.

---

## Features

- Custom Arch Linux live ISO
- Preinstalled packages
- Automated install scripts
- Custom configs (dotfiles, system settings)
- Reproducible builds

---

## Requirements

You need an Arch Linux environment:

```bash
sudo pacman -S archiso git
````

---

## 🔨 Build ISO

Clone the repo:

```bash
git clone https://github.com/arthur-pbty/arch-custom-iso.git
cd arch-custom-iso
```

Run build script:

```bash
chmod +x build.sh
sudo ./build.sh
```

---

## Output

After build:

```
out/archlinux-*.iso
```

---

## Structure

```
airootfs/        → live system files
packages.x86_64  → packages in ISO
scripts/         → install scripts
profiledef.sh    → ISO configuration
```

---

## Goal

This project aims to create a reproducible, fully automated Arch Linux installation ISO.

---

## License

MIT