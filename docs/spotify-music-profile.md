# Spotify music profile prototype

This implements Kamran's music import and taste-summary slice of the proposal. The proposal describes both Spotify and Apple Music; this prototype implements Spotify only. It does not implement romantic compatibility scoring. Shared account, discovery, match, and chat clients are now prepared but require the team's Firebase configuration and deployment before they connect devices.

## What works in code

Open the Profile tab. Connect Spotify with authorization code + PKCE, grant `user-top-read`, and import up to 10 top artists and 50 top tracks for `medium_term` (roughly six months). The user can select one imported song as their showcase. Refresh reimports the lists while preserving a showcase still present in the latest list. No showcase is selected automatically.

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

Spotify's artist genres field is deprecated and may be missing even for popular artists. Existing Spotify tags take priority. A small ID-keyed snapshot from MusicBrainz supplies immediate fallback for Drake, Kanye West, Freddie Gibbs, and Summrs, including the user's already-cached imported profile. Artist tags are shown individually with source attribution and contribute to the overall summary. Genres characterize an artist's catalog and are not per-song or per-listen classifications.

For other missing genres, a background pass checks only the top 10 imported artists through exact Spotify-URL relationships (never a name-only match). Spotify import returns immediately with available cached genres. Unambiguous matches retrieve MusicBrainz genres with positive community votes; each success is saved and displayed progressively. Positive metadata is cached for seven days and empty results for one hour. Check all missing genres bypasses empty-result caching. Requests share a rate gate of at least 1.1 seconds, with up to three attempts for temporary failures and respect for Retry-After. Network-wide failures pause the pass without failing Spotify import; foregrounding or the retry button resumes it. Leaving the foreground or disconnecting cancels the pass, and stale results cannot overwrite the profile. MusicBrainz lookups contain public artist URLs, with no Spotify OAuth token or user ID. Disconnect clears the metadata cache too.

Wikidata is an automatic second fallback after MusicBrainz, using its Spotify artist ID property (P1902) and genre property (P136). One batched query requests English genre labels for only the remaining missing artists (maximum ten), rejects ambiguous identities, and does not search by name. Existing Spotify, MusicBrainz, and explicit user tags remain unchanged. Positive/empty cache lifetimes are seven days/one hour, with explicit retry bypassing empty results. Requests use a descriptive User-Agent, bounded retries, and Retry-After backoff. Disconnect clears both metadata caches. A failed source leaves the imported music available; catalog completeness is not guaranteed. The top-ten cap also migrates previously cached 50-artist profiles and limits genre ranking to those ten.

My music displays coverage and the top 10 imported artists, with Add/Edit genre tags for each. Explicit user tags are labeled Your tags, persist separately in the device Keychain, override subsequent imports and background results, and contribute to genre ranking. Use catalog tags restores the original metadata and resumes missing lookups. Catalog gaps remain visible until edited; automatic complete coverage is not guaranteed. These are artist tags, not independently verified genre classifications for each song.

Sources: [Spotify artist genres](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks), [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API), [Drake](https://musicbrainz.org/artist/9fff2f8a-21e6-47de-a2b8-7f449929d43f), [Kanye West / Ye](https://musicbrainz.org/artist/164f0d73-1234-4e2c-8743-d77bf2191051), [Freddie Gibbs](https://musicbrainz.org/artist/21645c31-fe1c-45a4-955c-3e172b12c3f9). Bootstrap source metadata checked October 25, 2026.

Validation: app Swift sources typechecked for the simulator SDK. Executed state/genre checks cover disabling demo, connected-state precedence, saved preference restoration, artist identity, Spotify-tag priority, cached-profile compatibility, metadata provenance, exact-ID network resolution with mocked responses, cache reuse, 404 handling, offline fallbacks, and exclusion of OAuth credentials from metadata requests. Live MusicBrainz lookup and on-device UI interaction remain unverified.

## Three fictional women profiles for chat testing

After Spotify or InTune sign-in, Discover shows Ava (22), Maya (23), and Zoe (24) as explicitly labeled fictional test profiles. A right swipe or Like creates a local test match, adds that profile's unique scripted first message once, and opens the chat. You can reply and reopen separate threads from Home, Discover, or the Test chats section in Matches. These test conversations do not use Firebase and no messages are delivered to a real person.

Each thread persists in a separate entry of a device-only Keychain item. Spotify disconnect/new authorization and InTune sign-out clear the new test chats. Passing removes a card and offers Show passed test profiles again without erasing existing matches. Empty/oversized messages and unsigned-in sends are rejected. Incoming messages are labeled scripted, outgoing messages as saved on-device.

Validation: app sources typechecked and LocalTestProfileChecks executed successfully for adult fixture identities, sign-in gating, automatic matches, unique initial greetings, thread isolation, persistence, validation, clearing, and save failures. Native gestures remain unverified through screen access.

## Restarting test swipes

Use Settings → Test profiles → Reset test profiles, or the Reset test profiles button in Discover. It clears Ava, Maya, and Zoe's local matches and test conversations and restores all three cards. Swiping right again creates a fresh match and initial scripted greeting. Reset persists across relaunch; if storage fails, existing state is preserved. Spotify imports, appearance settings, and real shared Firebase matches/messages are unaffected.

## Showcase-song previews

The signed-in test cards now keep a chosen showcase song: Ava — Space Song (Beach House), Maya — Snooze (SZA), Zoe — Crime Pays (Freddie Gibbs & Madlib). Each shows its title/artist, available artwork, and Play/Pause. Their Apple song IDs were checked against live US iTunes lookup responses on October 27, 2026; all three returned previews and artwork. No audio files were downloaded during validation.

The same component appears for the user's selected Spotify showcase in My music/Home and for the showcase displayed on real shared cards. Existing selection and Firestore `showcase` fields are preserved: no backend schema change. Public Apple catalog lookup resolves previews by artist/title, or by fixed Apple IDs for the fixtures. Exact title and artist matching avoids substituting a cover, remix, or unrelated track. A regional/connection/unavailable state is shown when no matching preview exists. The original Spotify song link remains available for Spotify selections.

Previews stream through AVPlayer, are capped at 30 seconds, and start only on a button tap. Only one preview plays at once; playback stops on card change, leaving its view, backgrounding the app, or finishing. Metadata is cached in memory; the app does not save audio clips. The UI attributes previews to iTunes and links to the full song's store page.

Validation: app Swift sources typechecked; model/lookup checks passed for metadata decoding, exact song matching, secure media URLs, preserving the chosen song, shared-display parsing, request authentication separation, caching, and all three live test-song lookup results. Local test matching/chat/reset checks passed after the fixture changes. Actual on-device audio playback has not been verified.

References: [Apple Search API](https://performance-partners.apple.com/search-api), [Search result fields](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html).

## Spotify song links

View on Spotify is now the primary external song action, including verified direct track links for all three fictional test profiles. The Apple-supplied preview keeps only its small linked iTunes attribution. If an older shared profile contains just song/artist text, Find on Spotify opens a safely encoded Spotify search instead of inventing a track ID. Actual Spotify selections retain their original direct song URL. URL routing, matching, and source-code checks passed.

## Minimal vinyl preview treatment

The showcase artwork is now a record sleeve. Pressing Play slides out a pink-label vinyl, and the vinyl spins only when AVPlayer reports actual playback. The record stays inside while buffering. Pausing, finishing, or leaving returns it to the sleeve; resuming playback slides it out again. Reduced Motion disables the slide/spin. This treatment is shared across showcase cards; the remaining screens and swipe/match effects are unchanged. No turntable textures or new image assets are needed.

Validation: app Swift source typechecking passed. Actual animation/audio behavior still needs a manual simulator/device check; no screen or audio capture was used.

## Scrolling inside profile cards

All discovery cards now use a simultaneous directional drag recognizer, allowing vertical scrolling to start on a card rather than only above it. Initial vertical intent remains locked and cannot trigger a like/pass later in the same gesture. Horizontal swipes require a clear horizontal direction and more than 90 points of travel. Short or ambiguous drags snap back; buttons remain available. The same modifier is used for fictional test cards, shared profiles, and offline demo cards. App typechecking and directional gesture-policy checks passed. Physical scrolling still needs a manual simulator/device check.

## Jukebox Matches screen

Matches is now a minimal jukebox selection board with adaptive tiles, pink accents, selection codes, names, and showcase songs. Tap a test tile to open its local chat or a shared tile to open the existing shared conversation. Test and real match sections stay visibly separate. Empty selections show an honest empty state; nothing is auto-matched by this screen. Dark/light appearances and larger accessibility text are supported.

Local test tiles show a pink new-message light only when an incoming message follows the saved read marker. Opening the active chat marks visible messages read; your own outgoing messages do not create an unread light. Markers persist in the existing device-only test-chat store, decode older stored chats without losing messages, and clear on test-profile reset. Shared tiles do not invent unread indicators: shared unread tracking remains backend work. No Firebase schema change is required for the new layout.

Validation: app Swift source typechecking and local chat/read-state tests passed, including separate unread states, persisted markers, old-cache migration, and reset behavior. Actual native layout/navigation still needs manual simulator/device verification; no screen access was used.

Genre coverage validation: a 12-artist mocked batch passes without a five-artist cap, with progressive updates, cache reuse, explicit negative-cache retry, 503 recovery, malformed-artist isolation, and offline preservation. User-tag checks cover persistence round-trip, original metadata preservation, exact artist identity, and precedence after refresh. Full app sources typecheck; live catalog completeness and on-device UI interactions remain unverified.

Second-source validation: live exact-ID batch query returned 13 genre rows for Kendrick Lamar and Drake; production response decoding was checked against that response. Executed tests cover automatic MusicBrainz-to-Wikidata fallback, exact IDs, tag provenance, ambiguous-identity rejection, preserving existing/user tags, positive/negative caching, explicit retry, 503 recovery, offline preservation, unsafe query identifiers, and limiting a 42-artist fixture to ten lookups. The app sources typecheck; full coverage of the user’s personal top ten requires an in-app refresh. Sources: [Wikidata Spotify artist ID](https://www.wikidata.org/wiki/Property:P1902), [Wikidata Query Service](https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual).

Summrs regression (October 27, 2026): live MusicBrainz artist response and URL relationship confirm Spotify artist `5L15t6I0PQS9SBXbiklPEN` maps to `d538d883-3889-44ad-8f32-6167cf4d85ec`, with positive-vote genres plugg, pluggnb, southern hip hop, and trap. These are now in the exact-ID bootstrap catalog so saved profiles acquire them on launch without network lookup. The live Wikidata Spotify-ID query returned no match for this artist. Tests cover immediate fallback, upgrading an empty cached artist, preserving explicit tags, and rejecting name-only matches. [MusicBrainz source](https://musicbrainz.org/artist/d538d883-3889-44ad-8f32-6167cf4d85ec).
