# Feature research

How Belfry compares with other GitHub notification clients, and what to build next. Researched 2026-11-12 from each project's own pages (sources at the end).

## Built in 0.2

| Feature | Seen in |
|---|---|
| Mark done (leaves the inbox, unlike read) | Gitify, GitHub web, Octobox |
| Mute a thread (`ignored: true`, not just unsubscribe) | Gitify, Octobox, GitHub web |
| Done for a whole repo or view, with undo | GitHub web (bulk), Gitify (per group) |
| CI runs collapsed per repo and branch | Octobox and Trailer show CI status on rows |
| Keyboard triage (↑↓ ↵ E M, ⌘F) | Gitify, Octobox, Neat |
| Mark done when opened (opt-in) | Gitify |
| Group by repository | Gitify |

## Next, ranked

1. **Banner rules.** Banners only for failures on my open PRs or the default branch, with everything else going silently to the list. GitHub's own "failed only" switch is all-or-nothing.
2. **Include and exclude rules** on author (bot logins included), repo, reason and PR state. Gitify's strongest feature.
3. **Global hotkey** to open the panel.
4. **Repeat reminder** while a review request is still pending, every N minutes, as PullPing does.
5. **Participating only** toggle (`?participating=true`).
6. **Snooze and save.** Local only: GitHub has no API for either.
7. **Priority sort** from reason history, as Meteorite does.

## What GitHub's API can't do

- There are no snooze, save or mark-unread endpoints. Done is one-way, and a thread only returns when it has new activity.
- `DELETE` on a thread's subscription still notifies you if you watch the repo. Only `PUT {"ignored": true}` mutes it.
- Saved web filters, `author:`, `org:` and `is:check-suite` aren't exposed. Filtering beyond `all`, `participating`, `since`, `before` and per-repo has to happen in the app.
- Classic tokens only (`notifications` or `repo`). `per_page` maxes out at 50, and `X-Poll-Interval` can rise.
- Your own actions don't create notifications, including commits and comments your agents make as you.

## Sources

- https://github.com/gitify-app/gitify and https://gitify.io/faq/
- https://ptsochantaris.github.io/trailer/
- https://neat.run/
- https://octobox.io/documentation
- https://docs.github.com/en/rest/activity/notifications
- https://docs.github.com/en/subscriptions-and-notifications/reference/inbox-filters
- https://github.com/roypadina/PullPing/wiki
- https://github.com/nickzuber/meteorite
- https://graphite.com/docs/customize-pr-inbox
