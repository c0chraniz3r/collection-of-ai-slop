#!/usr/bin/env bash

# Interactive Arch Linux ISO Builder
# Requires: archiso installed (sudo pacman -S archiso)

set -e

echo "==============================================="
echo "   Arch Linux Interactive ISO Builder"
echo "==============================================="
echo

# --- Step 1: Choose profile ---
echo "Available archiso profiles:"
echo "1) baseline  (minimal)"
echo "2) releng    (official Arch ISO profile)"
echo
read -rp "Choose a profile (1 or 2): " PROFILE_CHOICE

if [[ "$PROFILE_CHOICE" == "1" ]]; then
    PROFILE="baseline"
elif [[ "$PROFILE_CHOICE" == "2" ]]; then
    PROFILE="releng"
else
    echo "Invalid choice."
    exit 1
fi

echo
read -rp "Enter a name for your custom profile directory: " CUSTOM_NAME
CUSTOM_DIR="$PWD/$CUSTOM_NAME"

echo "Copying profile..."
cp -r "/usr/share/archiso/configs/$PROFILE" "$CUSTOM_DIR"

echo "Profile copied to: $CUSTOM_DIR"
echo

# --- Step 2: Package selection ---
echo "Would you like to edit the package list (packages.x86_64)?"
read -rp "Edit now? (y/n): " EDIT_PKGS

if [[ "$EDIT_PKGS" == "y" ]]; then
    ${EDITOR:-nano} "$CUSTOM_DIR/packages.x86_64"
fi

# --- Step 3: Add custom files ---
echo
echo "You can add custom files to the ISO by placing them in:"
echo "$CUSTOM_DIR/airootfs"
echo
read -rp "Open airootfs directory now? (y/n): " EDIT_FS

if [[ "$EDIT_FS" == "y" ]]; then
    ${EDITOR:-nano} "$CUSTOM_DIR/airootfs"
fi

# --- Step 4: Edit profile metadata ---
echo
echo "Would you like to edit ISO metadata (profiledef.sh)?"
read -rp "Edit now? (y/n): " EDIT_META

if [[ "$EDIT_META" == "y" ]]; then
    ${EDITOR:-nano} "$CUSTOM_DIR/profiledef.sh"
fi

# --- Step 5: Choose work and output directories ---
echo
read -rp "Enter work directory (where temporary build files go): " WORK_DIR
read -rp "Enter output directory (where final ISO will be placed): " OUT_DIR

mkdir -p "$WORK_DIR" "$OUT_DIR"

# --- Step 6: Build ISO ---
echo
echo "Building ISO using mkarchiso..."
echo "This may take a while depending on package count."
echo

mkarchiso -w "$WORK_DIR" -o "$OUT_DIR" "$CUSTOM_DIR"

echo
echo "==============================================="
echo " ISO build complete!"
echo "Your ISO is located in: $OUT_DIR"
echo "==============================================="
