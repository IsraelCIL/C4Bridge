# Discovery Build Test

This is the first real-controller validation for C4Bridge.

## Expected environment

- Control4 Director OS 3.3.0+
- `C4Bridge.c4z` installed once in any room
- No bindings are required for this discovery build

## Expected Properties

After Director loads the driver, select the C4Bridge instance in Composer.

Expected:

- **Status** = `Ready (discovery complete)`
- **Director Version** = actual Director version
- **System Type** = controller type reported by Director
- **Project Location** = configured city/country when available
- **Discovery Summary** = for example:
  `12 rooms, 47 devices, 31 protocol drivers, 18 recognized, 29 unsupported`

The exact counts will vary by project.

## What "recognized" means in Step 2

Step 2 recognizes these proxy filenames:

- `light_v2.c4i` / `.c4z` → `light`
- `thermostatV2.c4i` / `.c4z` → `climate`
- `blind.c4i` / `.c4z` → `cover`

Recognized does **not** mean controllable yet. Step 3 implements and tests the first real adapter.

## What to report after installation

Please capture:

1. Director Version
2. System Type
3. Project Location
4. Discovery Summary
5. Any C4Bridge error/status text

A screenshot of the C4Bridge Properties pane is sufficient for the first pass.

If **Status** is not `Ready (discovery complete)`, also capture the C4Bridge Lua log line beginning with:

```text
[C4Bridge]
```

## Safety

This discovery build is read-only with respect to other project devices. It enumerates project metadata/devices and builds an in-memory registry. It does not yet send device-control commands or modify bindings/programming.
