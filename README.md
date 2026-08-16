# Heartbeat Music v0.1

Heartbeat Music is a native SwiftUI iPhone prototype that selects and plays music from heart rate. It has two modes—**Workout** and **Relax**—and never uses half-time or double-time BPM equivalence. It can use the built-in demo catalog or import BPM-matched tracks from one of the user's Spotify playlists. Matching, BPM data, and imported catalog data stay on the iPhone; there is no backend, account system, or database.

## Run it

1. Open `HeartbeatMusic.xcodeproj` in Xcode 15 or newer.
2. Select the **HeartbeatMusic** scheme and an iPhone simulator running iOS 17 or newer.
3. Press **Run**.
4. Choose a heart-rate source and select **Workout** or **Relax**. The Simulator source provides the 60–180 BPM slider. Turn **Sync to heart rate** off to freeze the current track while readings continue.
5. Spotify authorization and Myzone Bluetooth both require a physical iPhone. Install and sign in to the Spotify app, then tap **Connect** in Heartbeat Music. The first connection asks for playback control and read-only playlist access. Spotify may resume the last-played song as part of authorization.
6. Expand **Import a Spotify playlist**, tap **Load my playlists**, choose an owned or collaborative playlist, and tap **Import and find BPM**. A developer-configured GetSongBPM key is copied into the iOS Keychain on first launch; testers never handle this credential. The prototype examines at most the first 50 playable tracks per import.

Run the unit tests with **Product → Test** in Xcode, or run the platform-independent package tests from Terminal:

```sh
swift test
```

## How it works

The project deliberately separates inputs, decisions, and outputs:

```text
Simulator / Myzone / Watch ──▶ TrackSelectionEngine ──▶ TrackDestination
             │                         │                    │          │
     HeartRateSource             HeartbeatCore        Spotify     Apple Music
```

- `HeartbeatCore` owns the track model, broad 52–180 BPM mock catalog, two mode policies, direct tempo matching, smoothing, hysteresis, and conservative song/BPM-result validation. It has no UI or service dependencies.
- `HeartRateSource` is the input boundary. The simulator, Bluetooth/Myzone receiver, and Apple Watch placeholder all use the same BPM callback, so changing hardware does not affect matching.
- `TrackDestination` is the output boundary. `SpotifyTrackDestination` recognizes an imported track's opaque `spotify:track:…` ID and hands playback to Spotify App Remote. Apple Music can implement the same boundary later.
- `NowPlayingViewModel` coordinates those boundaries and publishes display state to SwiftUI.

`TempoMatcher` calculates the absolute difference between each track's actual BPM and the mode's target BPM, then selects the smallest difference. It always compares actual track tempos directly: 72 BPM is never treated as equivalent to 144 BPM, and 150 BPM is never treated as equivalent to 75 BPM. If the catalog has no close match, the nearest available actual BPM wins.

`TrackSelectionEngine` applies an exponential moving average to noisy samples and keeps the current track until a candidate is more than 3 BPM closer, preventing tiny changes near a track boundary from causing rapid switching.

### Modes

- **Workout Mode:** The target is the smoothed heart rate. Clearly better higher-BPM tracks can be selected normally as activity increases. A clearly better lower-BPM track must remain preferred for **3 minutes 30 seconds (210 continuous seconds)** before it is selected. If the heart rate recovers enough that the lower track is no longer preferred, the countdown resets. This prevents short rests between sets from being mistaken for a sustained wind-down.
- **Relax Mode:** The target is **15 BPM below** the smoothed heart rate. The nearest actual-BPM track is selected using the same smoothing and hysteresis, but without Workout Mode's 210-second slowdown hold.

The smoothing factor, 3 BPM switching advantage, 210-second Workout delay, and 15 BPM Relax offset are configurable core values.

## Myzone and Bluetooth heart-rate monitors

Heartbeat Music connects **directly to the physical monitor over Bluetooth**; it does not read the Myzone app or use a Myzone cloud API. `BluetoothHeartRateSource` scans for the standard Bluetooth Heart Rate Service (`0x180D`), subscribes to the Heart Rate Measurement characteristic (`0x2A37`), and converts both standard 8-bit and 16-bit measurements into BPM samples.

To test Myzone:

1. Run Heartbeat Music on a **physical iPhone**. The iOS Simulator cannot receive nearby Bluetooth accessory data.
2. Allow Bluetooth when iOS asks.
3. Wear and activate the Myzone monitor. Moistening the chest-strap contacts can help it wake up.
4. Select **Myzone** from Heart Rate Source. The app scans, connects, and displays `MYZONE LIVE` after the first reading.
5. If an older Myzone model does not appear, close the Myzone app temporarily in case the monitor supports only one Bluetooth connection, then tap **Scan again**.

The implementation is based on the standard Bluetooth profile, so compatible non-Myzone chest straps can also work.

## Spotify integration

The app uses Spotify's official iOS SDK 5.0.1 through Swift Package Manager. Its public configuration is:

- Client ID: `9ab83e8c62ec4011ba97b9d4eb1aac62`
- Redirect URI: `heartbeat-music://spotify-callback`
- iOS bundle ID: `com.heartbeatmusic.app`

`Info.plist` registers the callback URL and permits detection of the installed Spotify app. `SpotifyPlaybackController` uses Spotify's official session manager to request three limited scopes: App Remote playback control, private-playlist read access, and collaborative-playlist read access. It handles the callback, supplies the user token to both App Remote and Spotify Web API, subscribes to player-state changes, and plays exact Spotify track URIs. No Spotify client secret is stored in the app. A Spotify Premium account and the Spotify iPhone app are required for exact on-demand playback.

`SpotifyCatalogService` loads the current user's playlists with `GET /v1/me/playlists` and reads an owned or collaborative playlist through Spotify's current `GET /v1/playlists/{id}/items` endpoint. For this MVP, an import is capped at 50 playable tracks to keep the process understandable and avoid unnecessary third-party lookups.

Spotify no longer makes Audio Features/BPM available to new development-mode apps, so Heartbeat Music obtains tempo separately from [GetSongBPM](https://getsongbpm.com/api). For local development, put `GETSONGBPM_API_KEY = your_key` in `HeartbeatMusic/Configuration/LocalSecrets.xcconfig`; that file is ignored by Git. The app copies the configured value into the iOS Keychain on first launch, so testers do not need to enter it. Each lookup must match both normalized song title and artist; common labels such as “Remastered” and “Radio Edit” are ignored, but loosely similar titles are rejected. Tracks without a reliable result are reported and excluded rather than assigned a guessed BPM.

Successful URI/title/artist/BPM results are cached incrementally in Application Support on the device, so one failed lookup does not discard earlier work. Completed catalogs are remembered by Spotify playlist ID. Previously imported playlists show a checkmark, matched-track count, saved date, and a **Use saved BPM catalog** action; the last active real catalog also loads after an app restart. **Use demo** switches back to the mock catalog at any time. When the selection engine chooses a real track, its Spotify URI flows through the existing output boundary and App Remote plays it.

To request a GetSongBPM key during development, use `ios-app://com.heartbeatmusic.app` as the iOS app identifier. GetSongBPM requires a public backlink; this README includes the required link, so after the repository is published its GitHub README URL can be used as the backlink URL.

Development Mode is appropriate for this prototype but currently limits the app to five allowlisted Spotify users. Spotify authorization and playback must be tested on a physical iPhone because the Spotify iOS app is not available in the simulator.

### Current Spotify limitations

- In Spotify's current Development Mode, playlist-item access is limited to playlists owned by the current user or playlists where they are a collaborator.
- The app filters out playlists whose `items` metadata is absent, so only owned or collaborative playlists appear. To use another playlist during development, open it in Spotify and choose **Add to other playlist** to create an owned copy.
- The Spotify user must be added to the app's allowlist, and the app owner must have Premium.
- The BPM provider may not recognize every exact release or version. Unmatched tracks are intentionally skipped.
- Spotify and GetSongBPM network calls happen only while importing. Heart-rate matching uses the cached local catalog afterward.

## Project layout

```text
HeartbeatMusic/                 SwiftUI app and integration boundaries
Sources/HeartbeatCore/          Reusable, platform-independent matching engine
Tests/HeartbeatCoreTests/       Matching, smoothing, and hysteresis unit tests
Verification/                   Standalone logic check for limited toolchains
HeartbeatMusic.xcodeproj/       Native iPhone app, core, and test targets
Package.swift                   Fast command-line core testing
```

## Next integrations: Apple Watch and Apple Music

1. Add a watchOS companion target and HealthKit capabilities to both apps. The iPhone app already exposes an Apple Watch input choice and `AppleWatchHeartRateSource` relay boundary.
2. Request HealthKit authorization with clear heart-rate and workout usage descriptions.
3. Implement `HealthKitHeartRateSource`, keeping the existing callback contract.
4. On Apple Watch, use an active workout session to receive live heart-rate samples, then relay them to iPhone with WatchConnectivity when needed.
5. Handle permissions, missing/stale samples, workout lifecycle, and background transitions.
6. Keep raw HealthKit data on-device and feed only BPM samples into `TrackSelectionEngine`; mode behavior and matching logic remain service-independent.

After Spotify playlist matching is validated, Apple Music can be added as a second catalog/playback adapter without coupling MusicKit to the core engine. A friend with an Apple Music subscription can authorize their own account on a test device; no credentials need to be shared.
