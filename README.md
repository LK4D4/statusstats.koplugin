# statusstats.koplugin

Standalone KOReader plugin that shows:

- current session reading time and pages in the status bar
- today's reading time and pages in the status bar

It is designed to stay separate from KOReader core for now, so we can iterate in your own GitHub repo and keep changes flowing through pull requests.

## Current behavior

- `Today` values are read from KOReader's built-in `statistics` plugin when it is enabled.
- `Current session` is read from KOReader's built-in `statistics` plugin.
- Footer display is enabled by default.
- Alt status bar display can be enabled from the plugin menu.
- The plugin tries to reuse KOReader's current footer item separator.

## Plugin menu

After copying the plugin into KOReader's `plugins` directory, open:

`Main menu -> Status stats`

Options:

- current session
- today
- show in status bar
- show in alt status bar

Current session submenu:

- time spent reading this session
- pages read this session

Today submenu:

- time spent reading today
- pages read today

## Installation

### Manual install

1. Copy the `statusstats.koplugin` folder into KOReader's `plugins` directory.
2. Restart KOReader.
3. Enable KOReader's built-in `statistics` plugin if it is not already enabled.
4. Open a book, then go to `Main menu -> Status stats`.

### AppStore install

The long-term goal is to make this installable through [App Store plugin for KOReader](https://github.com/omer-faruq/appstore.koplugin).

That may not work yet until this plugin is published in its own GitHub repository and packaged in a way the AppStore plugin can discover and install, but it is the intended distribution path.

## Testing On Android Phone

Assuming your phone is Android:

1. Install KOReader on the phone.
2. Copy the `statusstats.koplugin` folder into KOReader's Android plugins directory.
3. Restart KOReader.
4. In KOReader, make sure the built-in `statistics` plugin is enabled.
5. Open a book and read for a few minutes.
6. Turn on `Show in status bar` in `Main menu -> Status stats`.
7. Verify that `Current session` time/pages change during the session.
8. Verify that `Today` time/pages match KOReader's own statistics screens for the same book/session context.

Good first checks:

- disable `Current session -> pages` and confirm only session time remains
- disable `Today -> time` and confirm only today's pages remain
- change KOReader's footer separator and confirm this plugin follows it
- suspend and resume KOReader and confirm the values still refresh

If you want the fastest loop, the most practical first test is to run it on Android with a short EPUB and compare the footer output against KOReader's built-in statistics page.

## Repo workflow

Recommended GitHub flow for this repo:

1. Protect `main`.
2. Let Codex work on feature branches only.
3. Open one small PR per feature or fix.
4. Merge only after you test the plugin on device or emulator.

## Next PR ideas

- let the user rename `Today` to something friendlier if KOReader wording suggests a better term
- offer short and long label styles for footer/header
- support session stats persistence across reopen/restart
- add average session speed and time-left estimates
