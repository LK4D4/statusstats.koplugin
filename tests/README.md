# Tests

This directory contains a small pure-Lua smoke test for
`statusstats.koplugin`.

The test stubs the KOReader APIs used by `main.lua` and covers the status text,
menu structure, and footer lifecycle behavior.

Run it from the repository root with any Lua 5.x interpreter:

```bash
lua tests/statusstats_spec.lua
```
