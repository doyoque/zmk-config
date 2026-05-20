# Corne ZMK Config

This repo contains a Corne (`nice_nano_v2`) ZMK setup with `nice_oled` on both halves.

## What Changed

### 1. Base layer typing lag fix
The base thumb keys were changed to direct layer-tap behaviors to remove tap-dance delay:

- `&lt LOW SPACE`
- `&lt RAI RET`

This keeps hold-for-layer behavior while improving typing responsiveness.

### 2. LOW <-> RAI toggle switching
A thumb combo was added to switch between `LOW` and `RAI` without using tap-dance:

- Combo key positions: `<38 39>` (both thumb LT keys together)
- In `LOW` layer: combo -> `&to RAI`
- In `RAI` layer: combo -> `&to LOW`

Combo tuning:

- `timeout-ms = <40>`
- `require-prior-idle-ms = <120>`

This makes switching intentional and reduces accidental toggles during fast typing.

### 3. ZMK Studio support
ZMK Studio support is enabled for both left and right builds:

- `CONFIG_ZMK_STUDIO=y` in `config/corne.conf`
- `snippet: studio-rpc-usb-uart` in each build target
- `cmake-args: -DCONFIG_ZMK_STUDIO=y` in each build target

### 4. Studio unlock key
`&studio_unlock` is available in:

- `LOW` layer (existing)
- `RAI` layer (added)

So you can unlock for Studio from either utility layer.

## Build Targets

Defined in `build.yaml`:

- `corne_left__nice_oled`
- `corne_right__nice_oled`

Both include Studio RPC snippet support.

## Flash

Use the helper script:

```bash
./flash.sh l path/to/corne_left__nice_oled.uf2
./flash.sh r path/to/corne_right__nice_oled.uf2
```

Or follow the steps in `flash.md`.

## Notes

- If combo switching triggers too easily, increase `require-prior-idle-ms`.
- If combo feels too strict, lower `require-prior-idle-ms` or increase `timeout-ms` slightly.
