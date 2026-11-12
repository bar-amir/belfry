# Belfry

A small native macOS menu-bar app that rings when something happens on GitHub.
Belfry polls your GitHub notifications and shows each new one as a native macOS
banner. Clicking a banner opens the pull request, issue or comment in your browser.

- Menu-bar bell with your unread count
- Dropdown of unread notifications grouped by repository. Click to open,
  ✓ to mark read, or "Mark all read"
- Banners show the title, repository and reason (review requested, mention,
  comment, CI and so on)
- Polls with `If-Modified-Since`, so an unchanged inbox costs a cheap `304`,
  and it waits at least as long as GitHub's `X-Poll-Interval` asks
- Never announces the same activity twice. The last-seen `updated_at` per
  thread is kept in `~/Library/Application Support/Belfry/seen-threads.json`
- Settings for the token (stored in the Keychain), poll interval, sound, and
  launch at login

Requires macOS 14 or later. Written in Swift and SwiftUI with no third-party
dependencies.

## Build and run

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
make run        # generate the project, build Release, launch
```

Or step by step:

```bash
xcodegen generate
xcodebuild -project Belfry.xcodeproj -scheme Belfry -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Belfry.app
```

To install, copy `build/Build/Products/Release/Belfry.app` into
`/Applications` (`make install`). Launch at login works best from there.

On first launch macOS asks whether Belfry may send notifications. Choose
**Allow**. Under System Settings → Notifications → Belfry, set the alert
style to **Banners** (or **Alerts** if you want them to stay until dismissed).

On first launch with an empty history, Belfry only shows banners for activity
from the last 24 hours and quietly marks everything older as seen.

## Creating the token

1. Open <https://github.com/settings/tokens/new?scopes=notifications,repo&description=Belfry>
   (Settings → Developer settings → Personal access tokens → Tokens (classic)).
2. Keep the `notifications` and `repo` scopes. `repo` is needed to resolve
   private pull requests and issues to their web URLs. Pick an expiry.
3. Generate the token, open Belfry → Settings…, paste it and click **Save**.

The token is stored only in your login Keychain, under the service
`io.github.baramir.belfry`. It never touches the repository or a config file.

For development you can skip the Keychain by setting `BELFRY_GITHUB_TOKEN` in
the environment when you run the binary directly:

```bash
BELFRY_GITHUB_TOKEN="$(gh auth token)" build/Build/Products/Release/Belfry.app/Contents/MacOS/Belfry
```

## A note on your own activity

GitHub doesn't notify you about your own actions. If scripts, bots or agents
push and comment using your account, Belfry won't ring for that activity,
because GitHub never creates the notification.

## Layout

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
Belfry/Sources/
  BelfryApp.swift           MenuBarExtra + Settings scenes
  AppDelegate.swift         notification permission, banner click → open URL
  NotificationStore.swift   polling loop, dedupe store, banners, actions
  GitHubClient.swift        REST calls, Last-Modified/Link handling, html URL resolution
  MenuContentView.swift     dropdown UI
  SettingsView.swift        token, interval, sound, launch at login
  Keychain.swift            token storage
scripts/make-icon.swift     draws the app icon into the asset catalog
```

## License

MIT
