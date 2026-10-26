# Gauge

A native macOS menu bar + dashboard app that tracks your AI coding quotas in one place.

## Features
- **Antigravity** quotas (5-hour / weekly limits per model group) via the local `agy /quota` command.
- **GitHub Copilot** premium requests via GitHub's billing API, with automatic fallback to a local estimate.
- **Copilot CLI stats** read from your local session history: time spent per model, requests, tokens,
  cache hit rate, reasoning tokens, TTFT and tokens/sec, code changes, daily charts, by project / client.
- Menu bar gauge, history charts, low-quota notifications, launch at login.
- Customization: theme, menu bar style, pinned limit, refresh interval, history retention, stats range,
  notification thresholds, custom CLI paths.

## Privacy
Everything runs locally. Gauge only reads numeric counters from Copilot CLI session files — never prompts,
responses or file contents. Tokens are stored in your macOS Keychain; nothing is sent anywhere except
requests to `api.github.com` for your own billing data.

## Requirements
macOS 14+, Swift 6 toolchain. Optional: [`agy`](https://antigravity.google) CLI, GitHub Copilot CLI, `gh`.

## Build
```sh
./scripts/build.sh            # -> build/Gauge.app
./scripts/build.sh --install  # also installs to /Applications and launches
```

## GitHub billing access
Either save a fine-grained token with **Plan: read** in Settings → Accounts, or sign in with `gh` and run
`gh auth refresh -h github.com -s user`. Without it, the Copilot card uses local CLI usage.

## License
MIT
