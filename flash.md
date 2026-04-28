# Flash NICENANO (left firmware)

## 1) Confirm device is connected

```bash
lsblk -o NAME,LABEL,MOUNTPOINT,FSTYPE,SIZE
```

Look for a small VFAT device labeled `NICENANO` (example: `/dev/sdd`).

## 2) Mount the device

Use `udisksctl` (works without manual `mount` as root):

```bash
udisksctl mount -b /dev/sdd
```

Expected output:

```text
Mounted /dev/sdd at /run/media/<user>/NICENANO
```

## 3) Copy firmware and rename to CURRENT.uf2

Example using the generated left firmware:

```bash
cp -f /home/euqoyod/Projects/zmk-work/firmware-artifact/corne_left__nice_oled.uf2 \
  /run/media/euqoyod/NICENANO/CURRENT.uf2
sync
```

## 4) Verify behavior

After copy, the board usually reboots immediately and the `NICENANO` mount disappears.
That is normal and indicates flashing was accepted.

You can confirm it is gone with:

```bash
lsblk -o NAME,LABEL,MOUNTPOINT | rg "NICENANO|sdd"
```
