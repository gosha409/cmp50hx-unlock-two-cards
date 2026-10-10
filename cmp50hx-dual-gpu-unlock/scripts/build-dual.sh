#!/usr/bin/env bash
# Build only: does NOT modify EFI System Partition, GRUB, kernel, or VBIOS.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="${1:-$HOME/cmp50hx-unlock-src/efi-unlock}"
DIST="${2:-$ROOT/dist}"
[[ -d "$UPSTREAM" && -f "$UPSTREAM/build.sh" ]] || {
  echo "Usage: $0 /path/to/cmp50hx-unlock/efi-unlock [output-dir]" >&2
  exit 2
}
command -v python3 >/dev/null
command -v file >/dev/null
command -v objdump >/dev/null

mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
cp -a "$UPSTREAM" "$TMP/efi-unlock"
WORK="$TMP/efi-unlock"

# Prefer the backup the author originally made of the pristine upstream file.
if [[ -f "$UPSTREAM/unlock50x_v1.c.orig" ]]; then
  cp "$UPSTREAM/unlock50x_v1.c.orig" "$TMP/pristine.c"
else
  TOP="$(git -C "$UPSTREAM" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$TOP" ]] || { echo "Missing clean original and git history" >&2; exit 1; }
  git -C "$TOP" show HEAD:efi-unlock/unlock50x_v1.c > "$TMP/pristine.c"
fi

python3 "$ROOT/scripts/patch_ordinals.py" \
  --input "$TMP/pristine.c" --output-dir "$TMP/generated"

# Kali/Debian gnu-efi uses multiarch paths, and newer binutils needs
# --output-target to convert ELF into PE/COFF EFI.
if grep -q -- '--target=efi-app-x86_64' "$WORK/build.sh"; then
  sed -i 's/--target=efi-app-x86_64/--output-target=efi-app-x86_64/g' "$WORK/build.sh"
fi
EFI_LIB="${EFI_LIB:-/usr/lib/x86_64-linux-gnu}"
[[ -s "$EFI_LIB/elf_x86_64_efi.lds" ]] || {
  echo "Missing linker script at $EFI_LIB. Install gnu-efi or set EFI_LIB." >&2
  exit 1
}

if git -C "$UPSTREAM" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$UPSTREAM" rev-parse HEAD > "$DIST/upstream-commit.txt"
fi
for IDX in 0 1; do
  cp "$TMP/generated/unlock50x_auto${IDX}.c" "$WORK/unlock50x_v1.c"
  rm -f "$WORK/50HXUNLK.EFI" "$WORK/unlock50x_v1.so"
  echo "Building ordinal $IDX ..."
  if ! (cd "$WORK" && EFI_LIB="$EFI_LIB" bash ./build.sh) > "$DIST/build-auto${IDX}.log" 2>&1; then
    tail -60 "$DIST/build-auto${IDX}.log" >&2
    exit 1
  fi
  EFI="$WORK/50HXUNLK.EFI"
  [[ -s "$EFI" ]] || { echo "Missing build output for ordinal $IDX" >&2; exit 1; }
  file "$EFI" | grep -Eq 'PE32\+.*EFI'
  objdump -p "$EFI" | grep -Eq 'Subsystem[[:space:]]+0000000a'
  cp "$EFI" "$DIST/50HX-AUTO${IDX}.EFI"
  sha256sum "$DIST/50HX-AUTO${IDX}.EFI"
done
printf '\nBUILD_DUAL_OK (not installed)\n'
