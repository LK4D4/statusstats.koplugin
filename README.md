# statusstats.koplugin

`statusstats.koplugin` is a KOReader plugin that shows reading statistics from
KOReader's built-in `statistics` plugin in the status bar.

It can display:

- reading time for the current session
- pages read in the current session
- reading time for today
- pages read today

Example output:

```text
S 12m 3p | T 48m 11p
```

Time values are shown in minutes, and values under one minute are rendered as
`<1m`.

## Requirements

- KOReader
- KOReader's built-in `statistics` plugin enabled

## Installation

### AppStore

Install the plugin through the
[App Store plugin for KOReader](https://github.com/omer-faruq/appstore.koplugin).

### Manual installation

1. Download this repository as a ZIP, or clone it.
2. Make sure the folder name is `statusstats.koplugin`.
3. Copy the folder into KOReader's `plugins` directory.
4. Restart KOReader.

## Usage

After installation, open:

`Tools -> Status stats`

Available options:

- `Session`
- `Today`
- `Show in status bar`
- `Show in alt status bar`
- `Show debug info`

In the `Session` and `Today` submenus, you can enable or disable time and page
counters independently.

## Notes

- Footer display is disabled by default.
- The plugin reuses KOReader's current footer separator when possible.
- Data comes from KOReader's built-in `statistics` plugin for the current book
  and the current day.

## Tests

This repository includes a small Lua smoke test for the status text and footer
integration logic.

Run it from the repository root:

```bash
lua tests/statusstats_spec.lua
```

GitHub Actions runs this smoke test automatically for pull requests and for
pushes to `main`.
