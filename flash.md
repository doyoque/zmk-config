# Flashing Firmware to nice!nano

This guide covers the Linux CLI flow for mounting the board and copying a new firmware file.

## 1) Put the board in bootloader mode

Double-tap reset on the nice!nano. The board should re-enumerate as a USB mass-storage device labeled `NICENANO`.

## 2) Find and mount the device

Run:

```bash
dev="$(lsblk -nrpo NAME,LABEL | awk '$2=="NICENANO"{print $1; exit}')"
[ -n "$dev" ] || { echo "NICENANO device not found"; exit 1; }
udisksctl mount -b "$dev"
```

Notes:
- This avoids fragile escaping and fails early if the label is not found.
- Typical mount path is `/run/media/<user>/NICENANO`.

## 3) Copy firmware

Replace `firmware.uf2` with your actual build artifact path:

```bash
cp firmware.uf2 /run/media/$USER/NICENANO/
```

The board should reboot automatically after the copy completes.

## 4) Safely unmount (recommended)

```bash
udisksctl unmount -b "$dev"
```

## Troubleshooting

- `NICENANO device not found`
  - Confirm bootloader mode (double-tap reset).
  - Run `lsblk -nrpo NAME,LABEL` and verify the label is exactly `NICENANO`.
- `Error looking up object for device`
  - Usually means `$dev` is empty or invalid. Print it with `echo "$dev"`.
- Permission issues when mounting/copying
  - Ensure your desktop session can use `udisksctl`, or retry in a session with storage permissions.
