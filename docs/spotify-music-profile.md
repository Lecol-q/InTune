# Spotify music profile prototype

This implements Kamran's music import and taste-summary slice of the proposal. The proposal describes both Spotify and Apple Music; this prototype implements Spotify only. It does not implement romantic compatibility scoring, discovery, accounts, or the match/privacy backend.

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

There is currently no Firebase SDK, Firebase project configuration, or Authentication integration in the repo. This prototype intentionally labels storage as device-local.

When the account/profile work is ready, add a repository that saves a bounded `MusicTaste` snapshot under the authenticated Firebase UID, for example `profiles/{uid}/music/overview`. Store `updatedAt`, `timeRange`, ordered artist/track IDs and display metadata, genre weights, and the selected showcase. Treat this as user-approved profile content. Store OAuth credentials separately from readable profile data; never include them in public profile documents. Clear imported data on disconnect in the server repository as well as on-device. On InTune sign-out, clear device cache and credentials to avoid account crossover.

Firestore rules must require an authenticated owner for writes. Public pre-match fields must be separated from private photos/contact data, since Firestore rules do not redact fields in an otherwise readable document. Backend ownership checks, profile sharing consent, Spotify attribution/branding, and disconnect/delete behavior must be implemented and tested before publishing profiles. Spotify supplies music data, not the user's InTune name, age, or biography.

Do not describe artist overlap as romantic compatibility or invent a Spotify-generated compatibility score. Any later similarity ranking should be a separate, explicitly explained product feature.

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

## Marc match and chat test

Signed-in Spotify users see Marc, age 24, as an explicitly labeled local test profile in Discover. His taste tags are underground hip hop, jazz rap, abstract hip hop, and boom bap. This fixture is separate from the general demo toggle and has no real remote account behind it.

Swipe right or tap Like Marc to create an automatic local test match and open the chat. The initial incoming greeting is labeled scripted; outgoing messages are labeled saved on this device. No messages are delivered to a person or server, and no replies are generated. Reopen the conversation from Discover or Home. Pass hides the card, with a Show Marc again action.

The match and transcript are stored in a separate Keychain item and cleared on Spotify disconnect or a newly authorized Spotify account. Sending requires both a connection and the local match. Empty or over-2,000-character messages are rejected; unsuccessful saves preserve the draft and show an error. Repeated likes preserve the original transcript.

Validation: all app sources typechecked. Executed MarcMatchChecks cover connection gating, pre-match send rejection, pass/retry, automatic match, duplicate prevention, message normalization/limits, persisted-state decoding, storage failures, and test-state deletion. Native UI gestures were not exercised through screen access.
