# C4Bridge

C4Bridge is an open-source, local-first management layer for Control4 homeowners.

The goal is to provide simple device control, scenes, schedules, and everyday automation without requiring homeowners to use Composer Pro for routine changes.

## V1 scope

- Control4 Director OS **3.3.0+**
- `C4Bridge.c4z` is assumed to already be installed in the Control4 project
- Installation method is outside the scope of this project
- Cloudflare Pages PWA frontend
- Browser connects directly to C4Bridge over the local LAN
- LAN-only in V1; no cloud relay and no port forwarding
- One owner account
- Pairing + authenticated local API
- Initial device adapters: lights, HVAC/climate, shades/covers
- Unknown devices are exposed as `unsupported`
- C4Bridge owns its own scenes, schedules, and automations
- No import of Composer programming, scenes, or schedules
- Fixed-time, weekday, sunrise/sunset, and offset scheduling
- Director location/timezone used for solar scheduling
- No automatic `.c4z` self-update in V1

## Design principle

C4Bridge depends on **Director**, not Composer.

```text
Cloudflare Pages PWA
        |
        | Local Network Access permission
        v
Browser
        |
        | LAN only
        v
C4Bridge.c4z
        |
        v
Control4 Director
        |
        v
Existing Control4 devices
```

## First milestone

1. Detect Director version and reject versions below 3.3.0.
2. Read system/project metadata.
3. Discover rooms and devices.
4. Preserve Control4 proxy/protocol relationships.
5. Normalize discovered entities into an internal registry.
6. Classify known proxies and mark everything else as unsupported.
7. Add light state/control only after discovery is reliable.

## Status

Early development. The protocol and driver internals are not yet stable.

## Disclaimer

C4Bridge is an independent open-source project and is not affiliated with or endorsed by Control4 or Snap One.

Installing third-party drivers or modifying a Control4 project can introduce compatibility, support, warranty, or recovery risks. Users are responsible for understanding those risks and should keep appropriate backups of their Control4 project.


## License

C4Bridge is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
