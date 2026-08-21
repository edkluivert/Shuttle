# Shuttle

Move files between the devices in front of you, over the network they are
already on — or over a USB cable when there is no network at all. Nothing
leaves the LAN, no account is involved, and the device at the other end does
not need this app installed.

Flutter, targeting macOS, Windows, Android and iOS from one codebase.

---

## Contents

- [The three routes across](#the-three-routes-across)
- [Architecture](#architecture)
- [How each feature works](#how-each-feature-works)
  - [Sharing — the HTTP server](#sharing--the-http-server)
  - [The browser page](#the-browser-page)
  - [Discovery — finding other devices](#discovery--finding-other-devices)
  - [Transfer — the peer screen, both directions](#transfer--the-peer-screen-both-directions)
  - [USB — browsing a phone over the cable](#usb--browsing-a-phone-over-the-cable)
  - [History](#history)
  - [Opening a received file](#opening-a-received-file)
  - [Identity](#identity)
  - [Appearance](#appearance)
  - [Navigation](#navigation)
  - [macOS window chrome](#macos-window-chrome)
- [Wire protocol](#wire-protocol)
- [Where things are stored](#where-things-are-stored)
- [Platform configuration](#platform-configuration)
- [Dependencies](#dependencies)
- [Project layout](#project-layout)
- [Running and building](#running-and-building)
- [Tests](#tests)
- [Security model — read this](#security-model--read-this)
- [Known limits](#known-limits)

---

## The three routes across

The app deliberately offers three, because the right one depends on what the
other device is and what network exists.

| Route | Other device needs | Transport | Where it lives |
|---|---|---|---|
| **Browser** | A web browser | HTTP over Wi-Fi | `features/sharing` |
| **App to app** | This app installed | HTTP + mDNS over Wi-Fi | `features/discovery`, `features/transfer` |
| **USB** | A cable, and a computer at this end | `adb` or MTP | `features/usb` |

The in-app **How it works** screen (`features/shell/.../guide_page.dart`) says
the same thing to the user, with this device's live address filled in.

---

## Architecture

Clean architecture, one folder per feature, three layers each:

```
features/<name>/
  domain/        entities, repository interfaces, use cases   — no Flutter, no I/O
  data/          data sources, repository implementations     — sockets, files, processes
  presentation/  blocs/cubits and pages                       — Flutter
```

Dependencies point inward: `presentation → domain ← data`. A page never
touches a data source, and a data source never knows a bloc exists.

### The DI rule

`lib/core/di/injection.dart` wires everything through `get_it`, and encodes one
rule:

> **Data sources, repositories and use cases are singletons. Blocs and cubits
> are factories.**

A running HTTP server, an mDNS registration and a transfer log have to outlive
any screen, so they are registered once with `registerLazySingleton`. State
holders must not — a singleton bloc ties a server's lifetime to a widget's,
keeps emitting into closed screens, and lets any part of the app reach in and
mutate another screen's state. Every `registerFactory` hands a fresh instance
to whichever page asked, and that page disposes it.

`PeerFilesCubit` uses `registerFactoryParam` so each peer screen gets its own,
built around that peer's host and port.

### Shared state without singletons

`AppScope` (`features/shell/.../app_scope.dart`) sits in a go_router
`ShellRoute` and provides `IdentityCubit`, `SharingBloc`, `DiscoveryCubit` and
`HistoryCubit` once, around every route.

This is load-bearing: go_router's nested `routes:` are **not** widget
descendants of their parent — they are siblings pushed onto the same navigator.
Providing the blocs inside the home page left every pushed screen outside them,
and opening the guide threw `ProviderNotFound` the moment it read the server
address. Only a shell nests widgets.

### `currentAndChanges` — streams with no gap

`lib/core/utils/current_and_changes.dart` is used by every repository that
exposes a `watch()`. It emits what something has *now*, then every change,
with no window in between.

The obvious spelling is wrong:

```dart
Stream<T> watch() async* {
  yield current;            // ← runs a turn LATER, not on listen
  yield* _controller.stream;
}
```

An `async*` body does not run when `listen` is called, so anything emitted in
between is lost and the first value delivered is whatever `current` had already
become. `Stream.multi` runs its callback synchronously on subscribe, so the
initial value and the subscription happen in the same turn.

### Errors

`lib/core/error/` has a sealed `Result<T>` (`Ok` / `Err`) and a sealed
`Failure` hierarchy (`NetworkFailure`, `StorageFailure`, `DeviceFailure`,
`CancelledFailure`, `UnexpectedFailure`). Dart 3's exhaustive switches cover
what `Either` would have been imported for:

```dart
switch (result) { Ok(:final value) => …, Err(:final failure) => … }
```

Only calls with more than one interesting outcome return a `Result` —
`listFiles` does; `share()` does not.

---

## How each feature works

### Sharing — the HTTP server

**`features/sharing/data/data_sources/http_server_data_source.dart`** ·
`dart:io` `HttpServer`, no server package.

Binds `InternetAddress.anyIPv4` on port **53317**, falling back to an ephemeral
port if it is taken (usually another copy of the app on the same machine). The
fixed port is what makes `adb forward` possible — that command needs a port you
can name in advance.

Serving details worth knowing:

- **Only files the user picked are reachable.** The server holds a
  `List<File>`; `/download/<i>` indexes into it. There is no path traversal
  surface because there are no paths in the URL, and this is not a browser of
  the whole disk by design.
- **Uploads are sanitised.** `_safeName` strips any directory component, so
  `../../.ssh/id_rsa` lands in the inbox as `id_rsa`.
- **Collisions do not overwrite.** `photo.jpg` → `photo (1).jpg`.
- **Failed uploads leave nothing.** The partial file is deleted, because a
  truncated file looks like a real one in the Received list.
- **Filenames survive Unicode.** `Content-Disposition` is written both ways —
  plain ASCII for old clients and RFC 5987 `filename*=UTF-8''…` — so
  `Fotos für Ana.zip` keeps its name.
- **Content types** are mapped for the common image/video/audio/document
  extensions so browsers preview instead of downloading blobs.
- **`onError` on the listener** — without it a single malformed request kills
  the server while the app goes on claiming it is sharing.
- Every completed transfer is pushed onto a broadcast `Stream<ServedFile>`.
  The *repository* subscribes and writes the history entry; the data source has
  no business knowing a log exists.

`NetworkInterface.list` supplies every non-loopback IPv4, minus `169.254.*`
self-assigned addresses. More than one usually means Wi-Fi plus a USB tether,
and only one of them is the one the other device is on — so the UI offers all
of them rather than guessing.

### The browser page

**`features/sharing/data/data_sources/web_page.dart`** · a Dart string, no
templating engine, no assets.

Served at `/`. Plain HTML/CSS/JS: it lists the shared files (polling
`/api/files` every 4 s so the list stays live), and has a drop zone that
uploads via `XMLHttpRequest` `PUT` with real progress events.

It renders two different pages. If the request comes from the machine running
the server — loopback, or one of this device's own addresses — it shows the
address in large type with instructions instead of the transfer UI. Opened on
the serving machine the normal page is nonsense: half of it offers to send the
device's files to itself, and it is an easy mistake to make when you copy the
address to check it works and paste it into the browser already in front of
you.

### Discovery — finding other devices

**`features/discovery/data/data_sources/mdns_data_source.dart`** ·
[`nsd`](https://pub.dev/packages/nsd) (Bonjour / mDNS-SD).

Advertises `_shuttle._tcp` with the device name as the service name and the
device id in a TXT record under the key `id`.

- **Self-filtering is by id, not name.** Comparing display names meant two
  devices that happened to share one hid each other; an id cannot collide and
  survives a rename.
- **`ipLookupType: IpLookupType.v4`** is requested up front. Bonjour otherwise
  hands back a `.local` hostname, which resolves on Apple platforms but not
  reliably on Android — asking for addresses means every peer arrives with an
  IP that can actually be dialled.
- A peer with no resolved address is shown as still resolving rather than
  offering a tap that would fail (`Peer.isReachable`).
- **One row per device id, not per registration.** Bonjour renames a clashing
  instance rather than replacing it, so a device that re-registers without
  unregistering first is advertised twice — "iPhone" and "iPhone (2)" — and
  listing both asks the user to guess which is real. Where two registrations
  share an id, the one that resolved to an address wins.
- **The registration is torn down on `AppLifecycleState.detached`** as well as
  in `dispose`, which is not guaranteed to run when the process is killed. A
  registration left behind advertises a port nothing will answer on, and shows
  up on every other device as a real, tappable entry.
- Registration happens only *after* the server is up and has a port. Announcing
  a port nothing is listening on would put a dead entry on the network.
  Renaming the device re-publishes the registration.

A browser will never appear in this list — it has nothing to announce. That is
expected, and the guide screen says so.

### Transfer — the peer screen, both directions

**`features/transfer/`** · [`dio`](https://pub.dev/packages/dio).

Tapping a device on the Receive tab opens a screen for that device: whether
the two are connected, what has passed between them, and what the peer is
offering. Both directions live here — pulling is `GET /api/files` then
`GET /download/<index>`, and sending is `PUT /upload?name=…`, the same
endpoint the browser page uploads through, so the receiving end needed no new
code to accept it.

The screen was a bare list of the peer's files, which made the Receive tab
read as a dead end: you tapped a device you had just found and got a folder,
with no sign the two were connected and no way to send anything back.

- **Per-device activity comes from the shared log**, filtered on the peer's
  address. That is all either side ever knows the other by — the server
  records the address a request came from, and the client records the address
  it dialled. A peer reachable on two interfaces at once (Wi-Fi and a USB
  tether) files its transfers under whichever it used.
- **A peer announces itself with an `x-shuttle` header** on every
  request. Without it the receiving device logged a phone running this app
  identically to someone who had typed the address into a browser, and a
  per-device activity list is only meaningful if a peer's transfers are
  attributable. A browser never sends it, so old clients and old servers both
  keep working.
- **Uploads are streamed from disk with an explicit `Content-Length`.** dio
  cannot work the length out from a stream, and without it the request goes
  out chunked and the receiver has no total to draw a bar against. Streaming
  means a 4 GB video costs no more memory than a photo.
- **A failed push leaves nothing on the receiver** — it deletes its own
  partial file, which is the same cleanup a failed browser upload gets.
- **`connectTimeout: 8s`, and deliberately no receive timeout.** A peer that
  has left the network should fail in seconds rather than hang the button; a
  big file over slow Wi-Fi is not a stuck request.
- **Downloads are sequential.** The files share one link, so running them at
  once just makes every bar slower and none of them meaningful.
- **Written to `<name>.part`, renamed on success.** A cancelled or failed
  transfer must not leave something that looks finished. `.part` files are
  filtered out of the Received list.
- **Cancellation** is a `dio` `CancelToken`; `isCancellation` lets the
  repository tell a user cancel from a real error and stay quiet about it.
- **`TransferRate`** (in `transfer_progress.dart`) exponentially smooths the
  byte rate (α = 0.3, samples no closer than 250 ms). USB and Wi-Fi both
  deliver in bursts, and a figure flickering between 2 MB/s and 40 MB/s is
  worse than none. `TransferProgress` also carries the batch position, because
  being told only about the current file reads as a bar that keeps restarting.

### USB — browsing a phone over the cable

**`features/usb/`** · `Process.run` against external tools. Desktop only —
`UsbCubit.isSupportedPlatform` is macOS/Windows/Linux, because only a computer
can be the USB host.

Two backends behind one `UsbBackend` interface, tried in order. USB is not a
network: the cable carries a device protocol, and which protocol is available
depends on what the phone exposes and what the computer has installed. Rather
than pick one and fail on everyone else's setup, the app asks each backend
whether it can work here and uses the first that can.

**1. `AdbBackend` — `adb`.** Preferred where available: faster, reports real
errors instead of silently truncating, and gives real folders. Needs USB
debugging on the phone.

- Resolves `adb` from PATH plus `~/Library/Android/sdk/platform-tools`,
  `~/Android/Sdk/platform-tools`, `/usr/local/bin`, `/opt/homebrew/bin` —
  Android Studio installs it but does not put it on PATH.
- Lists with `adb shell ls -la`. The trailing slash on the path is
  load-bearing: `/sdcard` is a symlink, and `ls -la /sdcard` describes the link
  in one line instead of listing what is inside it.
- The `ls` line regex takes the name as *everything after the timestamp*, not
  the last whitespace-separated field, so `holiday photo.jpg` survives.
- Only devices in state `device` are listed; `unauthorized` and `offline` would
  just produce empty folders.

**2. `MtpBackend` — libmtp's CLI tools.** For phones that only expose MTP —
USB debugging off, or the user just picked "File transfer" on the phone's
prompt. Install with `brew install libmtp`.

It shells out rather than speaking MTP directly, and that is not a shortcut
taken lightly: MTP is a USB protocol, macOS ships no MTP support at all, and
Dart has no USB stack — the alternative is FFI bindings to libmtp and libusb
plus USB device entitlements.

**Why it indexes the whole phone up front:** libmtp's CLI has no "list one
folder" command; every tool walks the entire device before printing anything.
Measured on a Redmi Note 11S with 78,460 files — `mtp-folders` 1m45s,
`mtp-files` 2m59s. Listing on demand would cost minutes *per tap*. So the tree
is read once and cached; the first open is slow and the UI says so, and
everything after it is instant.

Two commands are needed, not one. `mtp-filetree` gives names, ids and structure
but marks nothing as a folder and carries no sizes; `mtp-files` lists only
files, with sizes — so it settles both questions. Without it an empty folder is
indistinguishable from a file. (`File size 665919 bytes` has **no colon** after
"File size", unlike every neighbouring field — reading it as `File size:`
reported every file on the device as 0 bytes.)

MTP is never scanned automatically. adb lists a device in well under a second;
MTP takes minutes, so it is opt-in from the backend picker — the automatic scan
only runs backends whose `scansQuickly` is true, and the no-phone screen points
at the picker when a slow one is installed.

**`mtp-detect` is not run at all.** It existed only to answer "is a phone
there?" before the walk, and every libmtp tool opens its own USB session —
each one another chance for the phone to leave File-transfer mode first. The
walk answers both questions itself: it names the device in its banner
(`Device 0 (VID=…) is a Xiaomi Mi-2s (MTP).` → `parseTreeLabel`), and it
returns in milliseconds when nothing is connected, so the fast "no phone"
answer survives. `devices()` hands back a provisional `Phone (MTP)` without
touching USB, and the first listing replaces the name or throws.

**A phone that leaves mid-browse is not an empty phone.** Every libmtp tool
opens its own session, so the device can answer one tool and be gone by the
time the next starts — Android reverts to charging-only when it locks, and
the USB device re-enumerates under a different product id (observed on a Redmi
Note 11S: `2717:ff48` → `2717:ff08` after one full walk). libmtp reports this as
`No raw devices found.` **on stdout, with exit code 0**, so neither the exit
code nor stderr can be used to spot it. Both backends therefore check the text
and throw `UsbDeviceGone` rather than returning an empty list, and the tree
cache only keeps a non-empty result — caching one failed walk used to make
every folder read as empty for the rest of the session.

**Progress** for both backends comes from `pollFileProgress`, which watches the
destination file grow every 200 ms. Both helpers print progress in different
formats to different streams, and `adb`'s is a bare percentage with no byte
counts — watching the file is uniform, needs no output parsing, and gives the
real byte figures the UI wants.

**Cancel stops after the file in flight.** The helper tools own the copy;
killing one mid-write would leave a truncated file behind.

### History

**`features/history/`** · JSON on disk.

Three features append to one log (`TransferWay.browser`, `.network`, `.usb`).
Held in memory in the repository — a singleton, because the screen showing it
is created and destroyed as the user navigates and the list has to outlive it.

- Capped at **500 entries**.
- Writes are **debounced 600 ms**: a batch of twenty files should write the log
  once, not twenty times. `dispose()` flushes anything still pending.
- A corrupt log is not worth failing to launch over — it is skipped, and so are
  individual entries written by a newer version.
- **Each entry records the file's local path**, which is what makes a row
  openable. Without it a log entry is only a name, and a list of names is not
  something you can tap. Every route supplies one: the inbox path for anything
  received, and the original path for anything sent — a file this device handed
  out is still here, it was copied, not moved.
- `existsLocally` checks the disk rather than trusting the log. Files get
  moved, renamed and deleted between a transfer and someone tapping the row,
  so a row whose file has gone says **"not on this device"** and does not
  respond to a tap, instead of opening nothing.
- Entries written before paths were logged simply have none. They still read
  correctly and are the same non-openable case.

### Opening a received file

**`lib/core/utils/open_file.dart`** ·
[`open_filex`](https://pub.dev/packages/open_filex) on the phones, the OS's own
command on desktop.

Every list that names a file will open it: the Received list, the Share tab's
activity, the per-peer activity, the History screen, and the share list itself.
A transfer that lands somewhere you cannot open is not finished, and these were
lists of names with no `onTap` at all.

Two mechanisms, because no one package covers both worlds. Android will not let
one app hand another a `file://` URI — it has to be wrapped in a `content://`
one through a FileProvider, which means native code, so the plugin earns its
place. The desktops each already ship a command that does exactly this
(`open`, `xdg-open`, `cmd /c start`) and need no dependency. Windows goes
through the shell rather than calling `explorer` directly, because `explorer`
exits non-zero even when it succeeded.

A tap that cannot work says why — the file is gone, or the phone has nothing
installed that reads that type. Silence is the one outcome worth avoiding.

### Identity

**`features/identity/`** · a random 8-byte hex id plus a display name.

The name defaults to the machine's own (`Platform.localHostname`, minus
`.local`), because that is what the person at the other end is looking for.
Renaming re-publishes the mDNS registration, and the browser page reads the
name at request time through a callback so a rename shows up without restarting
the server.

### Appearance

**`features/appearance/`** · six accents × light/dark/system, persisted.

`AppPalette` is a `ThemeExtension` read through a `context.palette` extension.
The accents are a closed set rather than a colour wheel: each is a hand-checked
pair (accent plus the soft tint behind it) that has to stay legible on both
grounds, and an arbitrary hex cannot promise that.

`AppearanceCubit` is provided *above* `MaterialApp` in `main.dart`, because the
accent has to rebuild the whole tree.

### Navigation

**`lib/core/navigation/`** · [`go_router`](https://pub.dev/packages/go_router).

Paths and names live together in `AppRoutes`/`RouteNames` so a typo is a
compile error rather than a blank screen. The peer screen is addressable by
host and port (`/peer/:host/:port?name=…`) rather than by whatever object the
caller happened to hold.

The router is built once and held in `_AppState` — rebuilding it on every theme
change would throw away the navigation stack with it. Secondary screens
(history, guide, appearance) rise from the bottom; they are detours from the
tabs, not steps deeper into them.

### macOS window chrome

**`macos/Runner/MainFlutterWindow.swift`** + **`lib/core/widgets/window_chrome.dart`**

The window is chromeless: `.fullSizeContentView` with a transparent titlebar
and hidden title, so the Flutter view runs the full window height and the top
strip picks up the app's own theme instead of AppKit's grey. Only the traffic
lights are drawn on top. Nothing has to be pushed to Swift when the theme
changes — the strip is Flutter pixels, so it follows the palette for free.

AppKit still owns that strip for *input*: it is the drag region that moves the
window, and it swallows clicks meant for whatever is painted below it.
`MacTitlebarInset` therefore adds 28 pt to `MediaQuery.padding.top`, wrapped
once around the shell route. That single wrap covers every screen — the
`SafeArea` in the tabs and the `AppBar` on every pushed page both grow by
`padding.top`. On Android and iOS the inset is zero and the padding passes
through untouched.

A control that needs to sit *beside* the traffic lights would have to be an
`NSView` overlay; a Flutter widget there is visible but not clickable.

---

## Wire protocol

Everything is plain HTTP/1.1 on port 53317 (or an ephemeral port if taken).

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | The browser page. Two variants — transfer UI, or the address page when viewed from the serving device itself. |
| `GET` | `/api/files` | `[{"name": "…", "size": 1234}, …]`, `Cache-Control: no-store` |
| `GET` | `/download/<index>` | The i-th shared file, with `Content-Disposition` |
| `PUT` | `/upload?name=<name>` | Body is the file; lands in the inbox |

Anything else is a 404.

**`x-shuttle: 1`** is sent on every request the app itself makes,
and never by a browser. The receiving server uses it only to decide whether to
log the transfer as a peer ("Wi-Fi") or as a browser. It is not a credential
and grants nothing — see the security section.

**mDNS:** service type `_shuttle._tcp`, service name = display name, TXT
record `id=<8-byte hex>`.

Bodies are streamed both ways (`file.openRead().pipe(response)`,
`sink.addStream(request)`) — nothing is buffered in memory, so file size is not
bounded by RAM.

---

## Where things are stored

**Received files (the inbox):**

| Platform | Path |
|---|---|
| macOS / Windows / Linux | `~/Downloads/Shuttle/` |
| Android | `/storage/emulated/0/Download/Shuttle/` |
| iOS | the app's Documents directory, `Shuttle/` |

The rule this follows: **a file must be findable without this app.** A transfer
that completes into a folder only the app can read has not really arrived — it
cannot be opened, attached to a message, or seen from a computer, and the
person is left looking at a list of files they cannot touch.

That is what the app used to do on Android. It wrote to
`getApplicationDocumentsDirectory()` — `/data/user/0/<pkg>/app_flutter/` —
which is private to the app and invisible to every file manager on the device.
Android now gets the real Downloads folder, verified writable on an Android 13
device with no permission requested and no entry in the manifest.

**Android candidates are probed, not assumed.** `_inboxDirectory()` tries the
public Downloads folder first, then the app's own folder on the shared volume
(`getExternalStorageDirectories`), and falls back to app documents. Each
candidate is tested by writing a byte and taking it back out, because Android
will report a directory as created and then refuse every write into it. Probing
rather than switching on the API level is deliberate: what shared storage
allows has changed with almost every Android release, and a vendor can be
stricter still.

**iOS needs two Info.plist keys, not a different path.** `UIFileSharingEnabled`
and `LSSupportsOpeningDocumentsInPlace` are what make the app's Documents
directory appear in the Files app under "On My iPhone → Shuttle".
Without them the folder is private, exactly as Android's was.

**Files left in the old location are moved on launch** (`_migrateLegacyInbox`).
Changing the destination without moving them would have looked like data loss.
Best-effort: a name already taken in the new folder is left alone rather than
overwritten, and a file that will not move is left where it is rather than
failing the launch.

The exact path in use is shown at the bottom of the Receive tab, with a button
to open the folder on desktop.

**App state** — `getApplicationSupportDirectory()`, e.g. on macOS
`~/Library/Application Support/com.kluivert.shuttle/`:

| File | Contents |
|---|---|
| `device_identity.json` | `{"id": "…", "name": "…"}` |
| `appearance.json` | `{"accent": "violet", "mode": "system"}` |
| `transfer_history.json` | The transfer log, newest first, capped at 500 |

All three are plain JSON, and all three tolerate corruption by falling back to
defaults rather than refusing to launch.

---

## Platform configuration

### macOS

**The sandbox is off, deliberately** (`macos/Runner/*.entitlements`). The app
drives helper binaries outside its container — `adb` in `~/Library/Android/sdk`,
libmtp in `/usr/local/bin` — and libmtp needs raw USB access. Measured with the
sandbox on: adb was unreachable from the app while working fine in a terminal,
and `mtp-detect` found no device. Temporary-exception entitlements cannot fix it
because the helper paths differ per machine. This is a local utility, not a Mac
App Store app — and App Store distribution would rule out USB tooling anyway.

The network, USB and Downloads entitlements are still declared: they cost
nothing, they document the intent, and they matter again the moment anyone
turns the sandbox back on.

`Info.plist` carries `NSLocalNetworkUsageDescription` and `NSBonjourServices`.
macOS 15 brought the iOS local-network prompt to the Mac, so the entitlements
alone are no longer enough.

`PRODUCT_NAME` lives in `macos/Runner/Configs/AppInfo.xcconfig` and drives the
bundle name, the menu bar, the Dock label and the window title. The `APP_NAME`
placeholders in `MainMenu.xib` resolve from it at launch.

### Android

`AndroidManifest.xml` requests `INTERNET`, `ACCESS_NETWORK_STATE`,
`ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` (mDNS needs multicast) and
scoped storage read/write.

**The Android Gradle Plugin is pinned to 8.13.2, not 9.** AGP 9 compiles
Kotlin itself and refuses any module that applies the Kotlin Gradle Plugin, and
this app's plugins are on opposite sides of that migration:

| Plugin | On AGP 9 |
|---|---|
| `file_picker` 11.0.3 | Detects AGP 9 and **skips** KGP, expecting built-in Kotlin |
| `nsd_android` 2.2.0 | Applies KGP **unconditionally** |

So neither value of `android.builtInKotlin` works. With it off, nothing
compiles file_picker's Kotlin and the app fails at
`GeneratedPluginRegistrant.java` with `cannot find symbol
com.mr.flutter.plugin.filepicker.FilePickerPlugin` — a confusing way for a
Gradle property to announce itself. With it on, AGP rejects `nsd_android`
outright. Both packages are already at their latest published versions, so
there is nothing to upgrade into.

AGP 8.13.2 with Gradle 8.14.3 builds cleanly, because on AGP 8 file_picker
applies KGP like everything else. Move back to 9 once `nsd` ships a build that
drops KGP. The `android.builtInKotlin` and `android.newDsl` flags in
`gradle.properties` are inert on AGP 8; Flutter's migrator re-adds them on
every build, so they are left in place.

`res/xml/network_security_config.xml` matters: transfers are plain HTTP, which
Android blocks by default from API 28. Rather than turning cleartext on
everywhere with `usesCleartextTraffic`, it is permitted **only** for RFC 1918
private ranges, link-local and `.local` names — the only places this app ever
connects to.

### iOS

`NSLocalNetworkUsageDescription` and `NSBonjourServices` in `Info.plist`.
Without the Bonjour service list this app's own type is filtered out even after
the user grants permission.

`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose the
received-files folder to the Files app — see [Where things are
stored](#where-things-are-stored).

### Linux and web

The `linux/` and `web/` directories are Flutter template scaffolding, not
supported targets. `nsd` ships no Linux implementation, so peer discovery is
unavailable there (the browser and USB routes would still work), and the app
imports `dart:io` throughout, which rules out web entirely.

---

## Dependencies

| Package | Used for | Where |
|---|---|---|
| [`nsd`](https://pub.dev/packages/nsd) | mDNS/Bonjour advertise + browse | `features/discovery` |
| [`dio`](https://pub.dev/packages/dio) | HTTP client, download progress, cancellation | `features/transfer` |
| [`file_picker`](https://pub.dev/packages/file_picker) | Picking files to share or push | `share_page`, `usb_page` |
| [`open_filex`](https://pub.dev/packages/open_filex) | Opening a received file with the phone's own viewer | `core/utils/open_file.dart` |
| [`path_provider`](https://pub.dev/packages/path_provider) | App support + Downloads directories | `core/di` |
| [`path`](https://pub.dev/packages/path) | Path joins, basenames, POSIX paths for the phone | throughout |
| [`flutter_bloc`](https://pub.dev/packages/flutter_bloc) | State management | all `presentation/` |
| [`equatable`](https://pub.dev/packages/equatable) | Value equality on entities and states | all `domain/` |
| [`get_it`](https://pub.dev/packages/get_it) | Dependency injection | `core/di` |
| [`go_router`](https://pub.dev/packages/go_router) | Declarative routing, shell route | `core/navigation` |

The HTTP **server** is `dart:io`'s `HttpServer` — no package. JSON is
`dart:convert`. USB uses `Process.run` against `adb` and libmtp's CLI.

**External tools** (USB tab only, desktop only, neither bundled):

| Tool | Install | Needed for |
|---|---|---|
| `adb` | Android Studio, or `brew install --cask android-platform-tools` | Android with USB debugging on |
| libmtp | `brew install libmtp` | Any phone in MTP "File transfer" mode |

---

## Project layout

```
lib/
  main.dart                      MaterialApp.router; AppearanceCubit above it
  core/
    di/injection.dart            get_it wiring, and the singleton/factory rule
    navigation/                  AppRoutes, AppRouter (ShellRoute + transitions)
    theme/app_theme.dart         AppPalette ThemeExtension, spacing, radii, accents
    error/                       sealed Result<T> and Failure
    utils/                       formatBytes, currentAndChanges
    widgets/                     SurfaceCard, PillNav, StatusPill, EmptyState,
                                 MacTitlebarInset, progress + selection bars
  features/
    shell/                       AppScope, HomePage (tabs + header), GuidePage
    sharing/                     HTTP server, browser page, Share tab
    discovery/                   mDNS advertise/browse, Receive tab
    transfer/                    peer file list + download, peer screen
    usb/                         adb + MTP backends, USB tab
    history/                     transfer log
    identity/                    device id and name
    appearance/                  accent + theme mode
macos/Runner/
  MainFlutterWindow.swift        chromeless titlebar
  Configs/AppInfo.xcconfig       PRODUCT_NAME, bundle id
  *.entitlements                 sandbox off, with the reasoning inline
test/                            117 tests, mirroring lib/
```

---

## Running and building

```bash
flutter pub get

flutter run -d macos
flutter run -d windows
flutter run -d <android-device-id>

flutter build macos --release
flutter build apk --release
```

Two devices on the same Wi-Fi is the fastest way to exercise the app-to-app
route. For the browser route, run one instance and open its address on a phone.

After changing `PRODUCT_NAME`, run `flutter clean` — the bundle path changes
and a stale artifact will linger.

### The macOS installer

```bash
./packaging/build_dmg.sh --build     # or omit --build to reuse the last release
```

Produces `dist/Shuttle.dmg`: the app, a symlink to `/Applications`, a custom
background and a volume icon. The artwork lives in `packaging/`, generated by
`assets/icon/generate_icon.py`.

Two things about that script are load-bearing. The background is a
multi-representation TIFF built with `tiffutil`, because a plain PNG renders
soft on Retina. And `.VolumeIcon.icns` is copied in *after* the Finder layout
pass — put it there any earlier and Finder deletes the file and clears the
custom-icon bit on its way out.

Builds are ad-hoc signed. On another Mac the first launch must be
right-click → Open, or the quarantine flag cleared with
`xattr -dr com.apple.quarantine "/Applications/Shuttle.app"`. Distributing
properly needs a Developer ID certificate and notarisation.

---

## Tests

```bash
flutter test
```

117 tests, all passing. They target the parts where the bugs actually were —
parsers, protocol behaviour and formatting — rather than widget trees:

| File | Covers |
|---|---|
| `test/features/usb/mtp_data_source_test.dart` | `mtp-filetree` / `mtp-files` parsing, the banner label, vanished-device detection, folder inference, the sizes-without-colon case |
| `test/features/usb/adb_data_source_test.dart` | `ls -la` lines: spaces in names, symlinks, permission suffixes |
| `test/features/sharing/http_server_data_source_test.dart` | Every endpoint, JSON escaping, non-ASCII filenames, upload sanitising, name collisions, 404 paths, the concurrent-start race, peer-vs-browser attribution |
| `test/features/transfer/http_transfer_data_source_test.dart` | The real client against the real server: push round trip, progress totals, collisions on the receiver, unreachable peers |
| `test/features/sharing/sharing_repository_test.dart` | Status stream, history recording, the two browser pages |
| `test/features/transfer/transfer_progress_test.dart` | Labels, ETA wording, rate smoothing under bursts |
| `test/features/history/history_repository_test.dart` | Persistence, ordering, corrupt-file and unknown-enum tolerance, relative time |
| `test/features/appearance/appearance_repository_test.dart` | Persistence, what each accent changes |
| `test/features/discovery/mdns_data_source_test.dart` | Self-filtering by id, collapsing a device advertised twice, what counts as dialable |
| `test/core/app_router_test.dart` | Route table, peer addressing and escaping |
| `test/core/formatters_test.dart` | `formatBytes` |

---

## Security model — read this

**The server is unauthenticated and unencrypted.** Plain HTTP, bound to
`0.0.0.0`, with no password, token or pairing step. While sharing is on, anyone
who can reach this device on the network can:

- list and download every file you have added to the share list, and
- `PUT` arbitrary files into your inbox folder.

The port is also announced over mDNS, so nothing needs guessing.

That is the correct trade for the problem it solves — the other end is a
browser with nothing installed, and TLS on a LAN with no CA means a certificate
warning on every transfer. But it means the app is only appropriate on a
network you trust. **Do not leave sharing running on café, hotel, airport or
campus Wi-Fi.**

What does limit the damage:

- Only files you explicitly added are served. The server has no notion of a
  filesystem path — `/download/<i>` indexes a list. It is not a file browser of
  your disk and cannot be turned into one.
- Uploaded names are stripped to a basename, so nothing can be written outside
  the inbox.
- Uploads never overwrite; they get a `(1)` suffix.
- Nothing is sent to the internet. There is no telemetry, no account, no
  server beyond the one on your own device.

---

## Known limits

- **No encryption or authentication.** See above.
- **No resume.** An interrupted download starts over; the `.part` file is
  discarded.
- **IPv4 only** for discovery (`IpLookupType.v4`), though the transfer client
  brackets IPv6 literals correctly if one is supplied.
- **Per-device activity is matched on IP address.** A peer that changes
  address — reconnects on a different network, or is reached over a USB tether
  after Wi-Fi — starts a fresh activity list. The device id in the mDNS TXT
  record would be the stable key, but the HTTP server only ever sees an
  address.
- **MTP's first scan takes minutes** on a phone with a large library, and MTP
  `push` ignores the current folder — libmtp's `mtp-sendfile` has no directory
  argument, so the file lands wherever its default is.
- **The MTP backend's tool search is Unix-oriented** (`/opt/homebrew/bin`,
  `/usr/local/bin`, `/usr/bin`, then PATH). On Windows it only resolves if the
  libmtp tools are already on PATH. `adb` resolves on all three desktops.
- **Android is held at AGP 8**, not 9 — see [Platform
  configuration](#android). The plugin ecosystem is mid-migration and two of
  this app's plugins currently want opposite things.
- **`cupertino_icons` is declared in `pubspec.yaml` but unused.** It is the
  Flutter template default and can be removed.
- **Builds are ad-hoc signed, not notarised.** The bundle id is real
  (`com.kluivert.shuttle`), but without a Developer ID certificate Gatekeeper
  blocks the app on any Mac other than the one that built it. See [Running and
  building](#running-and-building) for the DMG and the first-launch workaround.
