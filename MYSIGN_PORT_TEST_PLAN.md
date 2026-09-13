# MySign port — test plan

Everything carried over from MySign, where it lives, and what to check. Tick the
boxes as they pass; anything that fails is a bug with a named owner.

Build under test: `git rev-parse --short HEAD` — visible in the app as **Settings →
About** (`CFBundleVersion` is stamped from the commit).

---

## A. Repository browser

MySign's real strength. All of this lands in **Sources**.

- [ ] **Repository disk cache.** Force-quit, relaunch, open Sources. Repositories
      appear with their app counts *before* the network answers, then refresh in
      place. Previously every cold start re-downloaded and re-parsed every source.
- [ ] **Cache controls.** Settings → MySign → Repository Cache shows total size,
      file count, per-repository entries and last refresh; refresh and clear work.
      Clear, then relaunch: the list still loads (from network) and re-caches.
- [ ] **Favourites.** Repository context menu → favourite. The favourites section
      appears above the rest and survives a relaunch.
- [ ] **App icon backup.** A repository with **no icon of its own** borrows one of
      its apps' icons and keeps it. Refresh it from Repository Cache.
- [ ] **Icon tinting.** Repository rows and their chevrons take their colour from
      the icon; a greyscale/monochrome icon falls back without crashing.
- [ ] **App-count numbers.** Each row shows its app count. Sort by **most apps**
      puts the biggest repository first.
- [ ] **Compact rows.** One line per repository, ~30pt icon, count inline, URL
      gone. Check a long repository name truncates rather than wrapping.
- [ ] **Repository context menu.** Favourites, copy source URL, view raw JSON, and
      the debug screen all open without a crash.
- [ ] **Cross-repository news.** Sources → News. Announcements from *every*
      repository appear in one scroll, each drawn in full: artwork, headline in
      white over the artwork, caption, then source · date. Nothing happens when
      you tap a row (by design — there is no detail sheet).
- [ ] **Browse settings.** Settings → MySign → Browse. **Each switch must change
      something** — that screen's whole point is that its toggles are wired, not
      stored and ignored.
- [ ] **ESign export.** Repository context menu → export. The code that comes out
      is accepted by RyukSign's own Add Source field (round-trip).
- [ ] **Copy from an app row.** Long-press an app → Copy → icon URL, bundle ID.

## B. App container

- [ ] **Files tab.** Browse the app's container. Move, share, rename, compress and
      delete all work from the context menu; deleting a folder recurses; search
      filters as you type.
- [ ] **Image viewing.** Open an image from Files and page through its siblings.
      Pinch to zoom, dismiss, and land back on the right row.

## C. Downloads

- [ ] **Download history.** Settings → MySign → Download History. Each entry keeps
      its **icon, name, bundle ID, version, date and time**, and its status moves
      from *started* to *completed* when the import finishes. Clear works.
- [ ] **Icon survives a relaunch** (it is cached locally, not re-fetched).
- [ ] **Follow the download.** After a download completes, the app is highlighted
      in the Library and the highlight fades by itself.
- [ ] **Icon-only download button.** Every app row shows just a symbol, no "Get"
      text: outline `arrow.down.circle` when not installed, filled when an update
      is available, `clock.arrow.circlepath` for a downgrade. Still tappable, and
      the ellipsis menu beside it still opens.

## D. Tweaks

- [ ] **Default tweaks.** Settings → MySign → Default Tweaks. Picked tweaks inject
      into a new signature without re-picking, and the count badge on the Tweaks
      tab matches the selection.

## E. Feedback

- [ ] **Haptics and sounds.** Settings → MySign: the two toggles and the sound
      style picker affect real interactions (tab changes, downloads, drags).
      Turning both off makes the app silent without breaking anything.

## F. Tab bar

- [ ] **Style picker.** Settings → Tab Bar → Style → **Glass Switcher** replaces
      the system bar. Switching back restores it.
- [ ] **Glass.** On iOS 26 the rail and handle are real Liquid Glass
      (`glassEffect`), not a blur; on older iOS they fall back to the ultra-thin
      material recipe.
- [ ] **Placement.** Against the **right** edge, and centred a quarter of the
      screen *above* the middle.
- [ ] **Even spacing.** No circle behind the icon. The gap left and right of the
      icon + label is equal, and the gap between two rows matches it — nothing
      should look tighter vertically than horizontally.
- [ ] **Taps register.** Tapping a tab switches to it. This one was broken: an
      invisible edge-swipe strip sat over the rail and ate the taps.
- [ ] **Handle.** Tap to expand/collapse, long-press for the shortcut (collapsed →
      hidden, hidden → expanded), drag left to expand and right to collapse.
- [ ] **Arrow.** One chevron that **rotates** to the state and **leans** while
      dragging — it must never blink out and reappear.
- [ ] **Auto-hide.** Left alone for 10 seconds the handle fades; any interaction
      brings it back and restarts the timer.
- [ ] **Badges.** Source-update and default-tweak counts show on their tabs.
- [ ] **Edge reveal.** With the rail hidden, swiping in from the right edge brings
      it back.

## G. Performance

- [ ] **Cold start.** With a large source set cached, the first frame of Sources is
      not blocked by disk work — no multi-second frozen screen before the list.
- [ ] **Opening a huge repository** (15k+ apps) sections and sorts off the main
      thread. Scroll stays smooth; no dropped frames on open.
- [ ] **Jump-to-app** in a large repository scrolls to the *right* app — the
      section-letter lookup and the grouping must agree.
- [ ] **Scrolling a long app list** does not encode PNGs or build image contexts
      on the main queue.

## H. Signing, and the things that were deliberately left out

- [ ] **A normal signing flow still works** end to end (import, sign, install).
      Nothing in this port should have touched it — a regression here outranks
      everything above.
- [ ] **Not ported, on purpose:** Circlefy (dead on iOS 26), the wallpaper
      manager and the theming tab, the status-bar clock and its padding/device
      utilities, the welcome/onboarding sheet, MySign's bespoke UI kit, its
      floating dock, and the ZSign-coupled managers. If any of these turn up in
      the app, something went wrong.
