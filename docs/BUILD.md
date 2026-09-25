# Building C4Bridge.c4z

C4Bridge uses the standard Control4/Snap One `.c4z` package layout:

- `driver.xml` at the package root
- `driver.lua` at the package root
- additional Lua modules under `src/`

The entrypoint is declared by `driver.xml`:

```xml
<script file="driver.lua"></script>
```

and `driver.lua` loads the implementation with:

```lua
require("src.main")
```

## Official Driver Packager

The source manifest is:

```text
driver/C4Bridge.c4zproj
```

It is compatible with Snap One's Driver Packager. Build output should be named:

```text
C4Bridge.c4z
```

No encryption or Lua squishing is enabled during early development so that logs and package contents remain easy to inspect.

## Minimum Director version

The package declares:

```xml
<minimum_os_version>3.3.0</minimum_os_version>
```

C4Bridge also performs a runtime version check so an unsupported Director is rejected explicitly rather than failing later in discovery code.
