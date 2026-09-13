# MySign → RyukSign merge audit

A compare-and-contrast of the two codebases, done before porting anything.

- **MySign** (`gliddd4/mysignipasigner`) — 148 Swift files in the app target (~25k lines), plus
  a separate `Circlefy/` helper and `UI/` folder. Written ~2 years ago; never finished.
- **RyukSign** (`gliddd4/RyukSign`, upstream `faroukbmiled/RyukSign` → Feather) — 219 Swift files
  in the app target (~38k lines), plus `NimbleKit`, `AltSourceKit`, the widget, and tests.

The point of this document is to stop the merge from being "copy the old UI in". MySign has good
*ideas* and a handful of genuinely finished features; most of its custom UI was never wired up.

## How each claim below was checked

1. **Usage analysis** — every top-level type in MySign was matched against the rest of the
   codebase. A type with zero references outside its own file was never hooked up.
   Result: **32 of 145 declared types are dead** (`UniversalComponents`, `PaddingSettingsView`,
   `BackgroundBlurView`, `WelcomePopover`, `FileContentView`, `NovaImage`, all five
   `RepositoryMenu/RepoMenu*` sub-views, `AddToolbar`, `IPADetailsSection`, …).
2. **iOS 26 reality check** — features that depend on removed behaviour are not portable
   (Circlefy, the `/System` file browser).
3. **API/architecture comparison** — what RyukSign already implements, to avoid porting a
   worse copy of something that exists.

## Scoreboard

| Area | MySign | RyukSign | Winner |
| --- | --- | --- | --- |
| Signing engine & options | name/bundle-id/version + tweak inject | ~30 signing flags, Info.plist editor, entitlements editor, alt icons, dylib/framework injection, batch sign, Mach-O readers | **RyukSign** |
| Certificate management | folders, rows, password check | add/import/export, auto-import, IdentityVault, entitlements inspector, expiry pills | **RyukSign** |
| Tweak management | folder list + inject | analyzer, dependency inspector, per-file config, extraction from zip/deb/ipa, ElleKit/Substrate detection | **RyukSign** |
| Installation | ESign/`itms-services` only | local server + TLS + manifest, idevice/pairing tunnel, install queue, cleanup | **RyukSign** |
| Download engine | URLSession, speed samples | background sessions, pause/resume, Live Activity, speed tracker, App Intents | **RyukSign** |
| **Repo browser** | **disk-cached repos, favourites, rich repo context menu, news feed, big sort set** | batched concurrent fetch, UIKit table, news cards, premium filter, no cache/favourites | **MySign** (see below) |
| **App detail** | more info rows, screenshot gallery | good, but fewer fields | **MySign** (partially) |
| **Files tab** | full browser + context-menu ops + image cycling | *does not exist* | **MySign** |
| **Download log** | persisted with icon/name/description/date | in-memory only, no history | **MySign** |
| Theming / toast / nav | custom, half-dead | `Color.userTint`, window-based Toast with queue + haptics | **RyukSign** |
| Backup / storage / logs / web server / self-update | absent | present | **RyukSign** |
| CI + build | none | Makefile + release workflow | **RyukSign** |

## MySign's standouts, verified

These are the things worth taking. Each was read, not assumed.

### 1. Repository disk cache — the reason it "loads way faster"

`RepositoryCacheManager` persists **every repo's parsed JSON plus a per-repo timestamp** to
`full_repositories_cache.json`, and re-reads it on launch, so a 15,000-app source set renders
before the network responds. It also short-circuits recomputation with an
`identifier:appCount` fingerprint and only re-sorts when that changes.

RyukSign's `SourcesViewModel` fetches in batches of 4 with good coalescing, but keeps everything
in memory (`sources: [AltSource: ASRepository]`) — **a cold start always re-downloads and
re-parses every source**. This is the single highest-value thing to port.

### 2. Favourites + a real repository context menu

`FavoritesManager` stores favourite repo IDs in `UserDefaults`; favouriting pulls a repo to the
top of the ordered list, unfavouriting drops it below the favourite block. Long-press gives
Favourite / Copy URL / View JSON / Change Icon / Delete.

RyukSign has **no favourites at all** (zero matches repo-wide) and its source context menu is
Copy / Exclude / Delete. Genuine gap, cheap to close.

### 3. Files tab

A browser with rename / move / delete / share / compress / unzip / search in the context menu,
plus an image viewer you can page through. RyukSign has no file browser; "Open Documents" just
hands the container to the Files app.

Two parts are **not** portable: the `/System` browsing relied on a `poc()` sandbox escape that
does not work on current iOS, and the tree view rebuilt itself recursively on every render
(`filterItemsRecursively` calling `DispatchQueue.main.async` inside `body`) — that is the bug
that made big folders crawl.

### 4. Download log with metadata

`PersistedDownload` stores the **whole `App` object** alongside the URL, completion state, error
and `downloadDate`, so the Downloads tab shows icon, name, description, date and time across
relaunches.

RyukSign's `Download` is a plain non-`Codable` class — no persistence, no history. Worth adding,
but as a *separate* history model rather than by rewriting the download engine.

### 5. Smaller wins

- Auto-switching tabs when a download starts (`AppNavigationManager` already can switch tabs, it
  just isn't used for this).
- Image preview you can cycle through.
- More app-detail info rows.

## What is *not* being ported, and why

| MySign thing | Why it stays out |
| --- | --- |
| Circlefy (icon masking) | Depends on the ArkSigning/ChOma ObjC patch; **broken on iOS 26**. Confirmed by owner. |
| Wallpaper manager | Never finished (owner); also the settings section that would drive it is dead code. |
| Custom tab bar (`TabManager`, `FixedTabSwitcher`, `DockPositionCalculator`, `VariableBlur`) | 5 files, dead/unused; RyukSign already has an ordering + visibility tab bar (`TabBarPreferences`). |
| Custom navigation (`NavigationManager`) | Dead; RyukSign uses `NBNavigationView`. |
| `UniversalComponents` (1,480 lines), `MainButton` (700), `ButtonStyleShowcase`, `WideToggle` | Never wired up. |
| `ToastManager` (582 lines, own window stack) | Superseded by RyukSign's `Toast` (queued, de-duped, haptic-aware). |
| Padding / density control | Dead code; global density needs to touch every screen to mean anything. |
| Onboarding (`Welcome`, `NewInstall`, `ValidationManager`) | Present-but-unused; RyukSign's install setup screens already cover it. |
| `/System` file browse + `poc()` exploit | Sandbox escape, not viable (and not wanted). |
| ESign encrypted sources | A 5,055-byte obfuscated XOR key blob and no repo-side support for the format; not worth the weight until something actually consumes it. |
| ArkSigning / libzsign / CydiaSubstrate | RyukSign signs through the SwiftPM `Zsign` package; swapping engines would rewrite the signing path for no gain. |

## Port order

1. Repository disk cache (cold-start speed) — highest value.
2. Favourites + repository context menu.
3. Files tab (browse / rename / move / delete / share / zip / unzip / search + image paging).
4. Download history log with app metadata.
5. Auto-switch on download, extra app-detail rows, wider sort presets.
