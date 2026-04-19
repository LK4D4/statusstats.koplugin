## Tests

This directory contains a tiny pure-Lua smoke test for `statusstats.koplugin`.

It stubs the KOReader APIs that `main.lua` depends on and exercises the
footer text generation path. That path would have caught the `_()` shadowing
bug, because the test calls `getStatusText(false)` directly.

Run it with any Lua 5.x interpreter from the repository root:

```bash
lua tests/statusstats_spec.lua
```
