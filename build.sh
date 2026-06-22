#!/bin/bash
set -e

ISO_NAME="arch-custom-iso"

echo "====================================="
echo "   Building Arch Linux ISO"
echo "   Project: $ISO_NAME"
echo "====================================="

# Check archiso
if ! command -v mkarchiso &> /dev/null; then
    echo "[ERROR] archiso is not installed"
    echo "Run: sudo pacman -S archiso"
    exit 1
fi

# Clean previous build
echo "[1/3] Cleaning previous build..."
rm -rf work out

# Build ISO
echo "[2/3] Building ISO..."
sudo mkarchiso -v .

# Check result
if [ -f out/*.iso ]; then
    echo "[3/3] Build successful!"
    echo "ISO located in: out/"
else
    echo "[ERROR] ISO not found in out/"
    exit 1
fi

echo "====================================="
echo "Done."
echo "====================================="