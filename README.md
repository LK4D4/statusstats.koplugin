# statusstats.koplugin

Standalone KOReader plugin that shows:

- current-session and today's reading time and pages in the status bar

It is designed to stay separate from KOReader core for now, so we can iterate in your own GitHub repo and keep changes flowing through pull requests.

## Current behavior

- `Session` values are read from KOReader's built-in `statistics` plugin current-book session stats.
- `Today` values are read from KOReader's built-in `statistics` plugin.
- Footer display is off by default.
- Alt status bar display can be enabled from the plugin menu.
- The plugin tries to reuse KOReader's current footer item separator.
- Status text uses compact scope prefixes such as `S 12m 3p | T 48m 11p`.
- Plugin-rendered time values never show seconds; sub-minute values render as `<1m`.

## Plugin menu

After installing the plugin, open:

`Tools -> Status stats`

Options:

- session
- today
- show in status bar
- show in alt status bar
- show debug info

Session submenu:

- time spent reading this session
- pages read this session

Today submenu:

- time spent reading today
- pages read today

## Installation

### Manual install

1. Download or clone this repository.
2. Rename the repository folder to `statusstats.koplugin` if needed.
3. Copy that folder into KOReader's `plugins` directory.
4. Restart KOReader.
5. Enable KOReader's built-in `statistics` plugin if it is not already enabled.
6. Open a book, then go to `Tools -> Status stats`.

### AppStore install

The long-term goal is to make this installable through [App Store plugin for KOReader](https://github.com/omer-faruq/appstore.koplugin).

The repository is now structured like a standalone `.koplugin` repo, which is the right direction for AppStore compatibility, but AppStore discovery/install still needs to be verified on device.

## Testing On Android Phone

Assuming your phone is Android:

1. Install KOReader on the phone.
2. Download the GitHub ZIP or copy the repo folder to the phone.
3. Rename the extracted folder to `statusstats.koplugin` if the archive created a different folder name.
4. Copy it into KOReader's Android plugins directory.
5. Restart KOReader.
6. In KOReader, make sure the built-in `statistics` plugin is enabled.
7. Open a book and read for a few minutes.
8. Turn on `Show in status bar` in `Tools -> Status stats`.
9. Verify that `Session` and `Today` values match KOReader's own statistics screens.

Good first checks:

- enable both `Session` and `Today` and confirm the footer shows `S ... | T ...`
- disable `Today -> pages` and confirm only the today time value remains
- disable `Session -> time` and confirm only the session page value remains
- change KOReader's footer separator and confirm this plugin follows it
- suspend and resume KOReader and confirm the values still refresh

## Tests

There is also a small smoke test in [tests/statusstats_spec.lua](/C:/Users/lk4d4/Documents/Codex/2026-04-19-i-want-to-create-a-koreader/tests/statusstats_spec.lua).

It uses pure Lua stubs instead of a full KOReader runtime and focuses on the
footer text generation path. That is useful for catching regressions such as:

- crashes while building footer text
- scope-prefix formatting changes
- minute-only duration formatting regressions
- accidentally leaving temporary debug actions in the menu

If you have a Lua interpreter available locally, run it from the repo root:

```bash
lua tests/statusstats_spec.lua
```

GitHub Actions also runs this smoke test automatically for pushes and pull
requests to `main`.

If you want the fastest loop, the most practical first test is to run it on Android with a short EPUB and compare the footer output against KOReader's built-in statistics page for both session and today values.

## Repo workflow

Recommended GitHub flow for this repo:

1. Protect `main`.
2. Let Codex work on feature branches only.
3. Open one small PR per feature or fix.
4. Merge only after you test the plugin on device or emulator.

## Next PR ideas

- support session stats persistence across reopen/restart
- add average session speed and time-left estimates
