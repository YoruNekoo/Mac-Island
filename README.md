# Mac Island

Mac Island adds a notch to MacBooks that don't have one. A small black notch sits at the top-center of the screen; expand it to see what's playing, your battery, a timer and more.

## Requirements
- macOS 14 (Sonoma) or later
- A MacBook display without a physical notch. On a notched display the app hides itself.

## Features
- **Now Playing:** Apple Music and Spotify, with artwork and play/pause/next/previous
- **Battery:** level, with a flash when you start charging
- **Timer** and **Stopwatch**
- **Calendar:** your next event
- **Mic and camera indicator:** shows when the microphone or camera is in use
- **Downloads:** browser downloads in progress (name and size)
- **Settings** (menu bar icon → Settings): turn features on or off, launch at login, how the notch expands, accent color, haptics

## Install (unsigned build)
This build is not notarized by Apple, so macOS warns the first time.
1. Drag **Mac Island** to your **Applications** folder.
2. Open it. macOS says it can't verify the app. Click **Done** (or **OK**).
3. Open **System Settings → Privacy & Security**, scroll to the message about "Mac Island", and click **Open Anyway**. Confirm with your password.
4. Open the app again. It lives in the menu bar and has no Dock icon.

## Permissions
Each feature asks only when first used, and only if it's turned on. Nothing is sent anywhere.
- **Calendar:** to show your next event.
- **Downloads folder:** to show the name and size of downloads in progress. File contents are not read.
- **Automation (Music, Spotify):** to control playback and read album artwork.

To change them later: **System Settings → Privacy & Security → Calendars / Files and Folders / Automation**.

## Known limitations
- The mic/camera indicator can't tell you which app is using the device.
- Only Apple Music and Spotify are supported for Now Playing.
- Download progress shows the size so far, not a percentage.
- Unsigned builds may need permissions re-granted after each update.
- Launch at login may be unreliable on unsigned builds.

## Build from source
Needs the Swift toolchain (Xcode or Command Line Tools). From the repo root:

```sh
Scripts/build_app.sh
```

This builds a universal (arm64 + x86_64) release app at `build/MacIsland.app`, ad-hoc signed. The version is set in `Resources/version.env`. To regenerate the app icon, run `Scripts/make_icon.sh`.

## Releasing
```sh
Scripts/release.sh
```
Builds the universal app, signs it (hardened runtime, `Resources/MacIsland.entitlements`), verifies it, and writes `build/MacIsland-<version>.dmg` (version from `Resources/version.env`). The signing identity defaults to `Mac Island Signing`; override with `SIGN_IDENTITY="..."`.

Notarization later only needs an Apple Developer account, a **Developer ID Application** identity, and a `notarytool` keychain profile (created once with `xcrun notarytool store-credentials`). Then run:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="your-profile" Scripts/release.sh
```
No credentials are stored in the repo.
