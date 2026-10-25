# Spotify music profile prototype

This implements Kamran's music import and taste-summary slice of the proposal. The proposal describes both Spotify and Apple Music; this prototype implements Spotify only. It does not implement romantic compatibility scoring. Shared account, discovery, match, and chat clients are now prepared but require the team's Firebase configuration and deployment before they connect devices.

## What works in code

Open the Profile tab. Connect Spotify with authorization code + PKCE, grant `user-top-read`, and import up to 50 top artists and 50 top tracks for `medium_term` (roughly six months). The user can select one imported song as their showcase. Refresh reimports the lists while preserving a showcase still present in the latest list. No showcase is selected automatically.

Artist genre tags are normalized and deduplicated. Artist at rank r (starting at 1) contributes 1/r, divided equally across its tags. Genre scores are normalized to shares of available genre evidence. They are not Spotify play counts or listening-time percentages. Missing genre tags produce an artist-based summary, and no history produces an honest empty state. No AI model or audio feature endpoint is used.

The snapshot and OAuth tokens are stored separately in device-only Keychain items. Disconnect deletes both and removes the old demo's UserDefaults token. The screen also links to Spotify's app access settings so users can revoke authorization there. The prototype does not publish anything to other users.

## One-time Spotify setup

1. The owner of the existing Spotify app must rotate the client secret previously committed in `Services/Constants.swift`. Removing it from the current source cannot revoke it or remove it from Git history. The new login flow does not use the secret.
2. In the Spotify developer dashboard for the client ID in `Services/Constants.swift`, register `intune442://spotify-login-callback` exactly. If using a separate app, replace the public client ID there. Do not add a secret.
3. Confirm the app owner's Premium subscription is active and add demo users to the app's allowlist. New development apps have a five-user limit; some existing installations have grandfathered users.
4. Open `InTune_442.xcodeproj`, choose scheme `MyApp`, select a simulator or signing team/device, and run. Go to the person tab and connect. No playback or Spotify iOS App Remote connection is needed for profile import.
5. Verify login, consent denial, refresh after restarting, showcase persistence, missing-history behavior, and disconnect deletion with a real allowlisted Spotify account. Live OAuth and API access require this dashboard/account setup; a compile cannot verify them.

## Firebase handoff

The app-side Firebase REST integration is prepared. Project configuration is empty, no Firebase project has been created or deployed, and live multi-device operation is not verified. A teammate is handling Firebase setup/deployment. See [the backend handoff](../backend/README.md) for the exact proposed schema, rules, security tests, and activation steps. Keep collection/field names coordinated with CommunityStore.swift and FirebaseCommunityClient.swift.

Each user needs an InTune account in the same Firebase project, then explicitly selects Share my profile. Spotify login alone does not share data. Published fields are allowlisted and exclude tokens, emails, and photos. Real messages are separate from the labeled local test chats. Until the teammate configures Firebase, all previous device-local features still work.

## Checks

Run the deterministic model checks from the repository root:

```sh
mkdir -p ../work
swiftc -module-cache-path ../work/ModuleCache InTune_442/Model/MusicTaste.swift Tests/MusicTasteChecks.swift -o ../work/music-taste-checks
../work/music-taste-checks
```

Build without device signing:

```sh
xcodebuild -project InTune_442.xcodeproj -scheme MyApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ../work/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The old playground/preview macros were replaced with ordinary SwiftUI preview providers to avoid the installed toolchain's preview plugin failure. The old UIKit controller is a compatibility wrapper around the new profile view; the app now opens its existing HomeView tab interface instead of the starter Hello World view.

## Spotify references checked October 25, 2026

- [Top items and `user-top-read`](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks)
- [Mobile PKCE login](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)
- [Development mode requirements](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Data deletion, attribution, and platform policy](https://developer.spotify.com/policy)

## Validation of this prototype

- Xcode 26.6: simulator build passed for scheme MyApp with signing disabled.
- Executed model checks passed for genre weights, normalized/duplicate tags and IDs, missing data, showcase preservation/removal, and Codable round-trip.
- Live Spotify authorization, API responses, and UI interaction have not been tested with a real account.
- Firebase persistence and visibility rules are not implemented.
- Existing Shuffle code produces iOS deprecation warnings.

## Appearance settings

Tap the gear at the top-left of Home, Discover, or My music. Under Appearance choose System, Light, or Dark. The selection applies throughout the app immediately and persists using the separate `intune.appearance` preference. System is the default.

Validation: all app Swift sources typechecked successfully for the iOS simulator SDK after adding these settings. Live interaction was not inspected; screen access remains unused.

## Login callback troubleshooting

Callback validation accepts the host-only configured URI with either an empty path or explicit root slash. Scheme, host, port, non-root path, and the per-attempt OAuth state are still validated before token exchange. Missing or mismatched state is rejected. Tokens, authorization codes, and state values are not included in errors.

The original generic login-verification message did not identify which check failed. A root-slash rejection is reproduced in the callback tests, but the original on-device failure cannot be confirmed without retrying. Updated errors identify `callback_address`, `callback_path`, `state_missing`, `state_mismatch`, and other failure categories. Do not share full callback URLs or authorization codes when diagnosing a login.

## Demo visibility and genre enrichment

The demo toggle lives only in Settings and is hidden when a Spotify account is connected. Successful OAuth turns demo off before import finishes. On launch, the saved connection state overrides demo visibility. Turning demo off while disconnected removes sample badges, likes, counts, profiles, and music throughout Home, Discover, and My music. Disconnecting Spotify does not automatically re-enable demo. All screens observe one shared profile model.

Spotify's artist genres field is deprecated and may be missing even for popular artists. Existing Spotify tags take priority. A small ID-keyed snapshot from MusicBrainz supplies immediate fallback for Drake, Kanye West, and Freddie Gibbs, including the user's already-cached imported profile. Artist tags are shown individually with source attribution and contribute to the overall summary. Genres characterize an artist's catalog and are not per-song or per-listen classifications.

For other missing genres, each refresh attempts up to five new MusicBrainz lookups through exact Spotify-URL relationships (never a name-only match). Unambiguous matches retrieve MusicBrainz genres with positive community votes. Metadata is cached for seven days; unmapped artists are not assigned invented tags. Requests are spaced at least 1.1 seconds apart. Optional lookup outages stop further enrichment for that refresh without failing the Spotify import. Refresh again to check the next batch of uncached artists. MusicBrainz lookups contain public artist URLs, with no Spotify OAuth token or user ID. Disconnect clears the metadata cache too.

Sources: [Spotify artist genres](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks), [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API), [Drake](https://musicbrainz.org/artist/9fff2f8a-21e6-47de-a2b8-7f449929d43f), [Kanye West / Ye](https://musicbrainz.org/artist/164f0d73-1234-4e2c-8743-d77bf2191051), [Freddie Gibbs](https://musicbrainz.org/artist/21645c31-fe1c-45a4-955c-3e172b12c3f9). Bootstrap source metadata checked October 25, 2026.

Validation: app Swift sources typechecked for the simulator SDK. Executed state/genre checks cover disabling demo, connected-state precedence, saved preference restoration, artist identity, Spotify-tag priority, cached-profile compatibility, metadata provenance, exact-ID network resolution with mocked responses, cache reuse, 404 handling, offline fallbacks, and exclusion of OAuth credentials from metadata requests. Live MusicBrainz lookup and on-device UI interaction remain unverified.

## Three fictional women profiles for chat testing

After Spotify or InTune sign-in, Discover shows Ava (22), Maya (23), and Zoe (24) as explicitly labeled fictional test profiles. A right swipe or Like creates a local test match, adds that profile's unique scripted first message once, and opens the chat. You can reply and reopen separate threads from Home, Discover, or the Test chats section in Matches. These test conversations do not use Firebase and no messages are delivered to a real person.

Each thread persists in a separate entry of a device-only Keychain item. Spotify disconnect/new authorization and InTune sign-out clear the new test chats. Passing removes a card and offers Show passed test profiles again without erasing existing matches. Empty/oversized messages and unsigned-in sends are rejected. Incoming messages are labeled scripted, outgoing messages as saved on-device.

Validation: app sources typechecked and LocalTestProfileChecks executed successfully for adult fixture identities, sign-in gating, automatic matches, unique initial greetings, thread isolation, persistence, validation, clearing, and save failures. Native gestures remain unverified through screen access.
