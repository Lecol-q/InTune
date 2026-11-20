# Firebase handoff for InTune

This is the proposed contract used by the app-side integration. Coordinate changes to collection names, field names, account providers, and rules with the iOS code; do not independently deploy an incompatible schema.

**Status:** The team has created `intune-6ce55` with Email/Password enabled and a default Firestore database (reported by the project owner). The reviewed Firestore rules were deployed with explicit approval on November 3, 2026, and the active ruleset was read back and verified against the tested file. See [SETUP-LOG.md](SETUP-LOG.md) for configuration, validation results, limitations, and remaining live acceptance checks.

## Teammate setup

1. Use the team's **existing shared** Firebase project, `intune-6ce55`, for all five teammates. Firestore and Authentication must belong to this project; do not create another project.
2. Enable Firebase Authentication → Email/Password. Each person creates their own InTune account in the app. This account is separate from Spotify login. Email verification/password reset, account deletion, blocking/reporting, and abuse controls remain launch work, beyond this team prototype.
3. Create a Cloud Firestore **default database**. Do not deploy an open test-mode ruleset.
4. Register an app or obtain the Firebase project's public configuration. Put the project ID and **Web API key** into `InTune_442/CommunityConfig.json`. These identify the Firebase project; never add a service-account private key or admin credential to the iOS app. All teammates need this same config, plus independently allowlisted Spotify accounts for music import.
5. From `backend/`, install the locked test dependencies with `npm ci`, then run `npm run test:rules` (Node 22 and Java required). With Homebrew's keg-only Node 22, first run `export PATH="/opt/homebrew/opt/node@22/bin:$PATH"`. The test script uses the `demo-intune` emulator project, not production; no Firebase login is required.
6. After rules tests and review pass, obtain explicit approval before publishing the intended production rules. The CLI command, **only after approval**, is `npx firebase deploy --only firestore:rules --project intune-6ce55` from `backend/`. Firebase deployment/login is the teammate's responsibility.
7. Everyone rebuilds the same iOS version, creates their own InTune account, connects Spotify if desired, and explicitly selects **Share my profile**. Signing in alone does not publish a profile.

## Collections

| Path | Fields | Access |
| --- | --- | --- |
| `profiles/{firebaseUID}` | `ownerID`, `name`, integer `age` (18–120), `bio`, `artists` (up to 10 names), `genres` (up to 12 tags), `showcase`, boolean `active` | Only owner writes. Authenticated discovery reads active profiles. Existing match partners can read a hidden profile. No photos, emails, account IDs from Spotify, or tokens in this document. |
| `swipes/{fromUID}/outgoing/{toUID}` | `fromID`, `toID`, `decision` (`like`/`pass`), server `createdAt` | Only sender writes/lists. Sender or target can get that individual swipe. |
| `matches/{sortedUID1}__{sortedUID2}` | `members` (two UIDs), server `createdAt` | Creation requires reciprocal stored likes and active profiles. Only members read. Client uses sorted UID order consistently. |
| `matches/{matchID}/messages/{UUID}` | `senderID`, `text` (1–2,000 characters), server `sentAt` | Only members read/create; sender must equal authenticated UID. No message editing/deletion in this prototype. |

The app uses Firebase Authentication ID tokens with the Firestore REST API so Firestore Security Rules apply. It does not use a service account or bypass rules. Authentication tokens remain in device-only Keychain; passwords are not persisted.

## Match behavior

After a like is saved, the client checks the reciprocal swipe and creates the deterministic match only if both are likes. The database rules enforce the reciprocal-like requirement too. Refresh reconciles existing outgoing likes to recover from interrupted match creation. Simultaneous creation checks for an already-created match. A backend trigger can replace this client orchestration later while preserving the schema and authorization checks.

## Refresh and privacy behavior

Discovery refreshes on entry and with its Refresh button. Matches poll while their screen is active (8 seconds); an open chat polls every 3 seconds. These are polling clients, not Firestore realtime listeners. Reads and network use grow with active chats. The integration is intended for a five-person prototype, not a production-scale messaging service.

Publishing is explicit and includes only the allowlisted pre-match fields. Music changes are sent to the shared profile only when the user chooses Update shared profile. Hide profile excludes it from discovery; existing matches and chats remain. Signing out does not hide a previously shared profile; the UI says so. Photos are not uploaded or displayed at all by this integration. Fictional test profiles remain separate, clearly labeled local fixtures and are never inserted into Firebase.

## Two-device acceptance check

- With the same project config, Alice and Bob create separate InTune accounts and publish profiles. Each sees the other, not themselves.
- Alice likes Bob: no chat appears yet. Bob likes Alice: one shared match appears for both after refresh.
- Alice sends a unique message; Bob sees it after the chat refresh. Bob replies; Alice sees it.
- Eve cannot read either user's private swipe list or the Alice/Bob conversation.
- Hiding Bob removes him from new discovery but preserves Alice's existing chat access.
- Relaunch and sign in to the same account; shared profile, match, and transcript survive.

References: [Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth), [Firestore REST with Firebase ID tokens](https://firebase.google.com/docs/firestore/use-rest-api), [Security Rules emulator tests](https://firebase.google.com/docs/rules/unit-tests).

## Song-preview compatibility

Card audio previews use the existing `showcase` display string (song title, an em dash separator, and artist names). No new Firestore fields are required. Preview availability is resolved locally from Apple catalog metadata, and does not change which Spotify song was selected or which profile fields are published.
