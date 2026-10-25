# Firebase handoff for InTune

This is the proposed contract used by the app-side integration. Coordinate changes to collection names, field names, account providers, and rules with the iOS code; do not independently deploy an incompatible schema.

**Status:** No Firebase project has been created or deployed by Codex. App Swift source typechecking passed. Executed REST/model checks passed for config validation, deterministic match IDs, public-profile field allowlists, Firestore encoding, authenticated requests, server timestamps, missing results, and sign-out. These mocked checks are separate from live backend validation. The Firestore rules and emulator test suite need to be executed and reviewed by the teammate handling Firebase before deployment.

## Teammate setup

1. Create **one shared** Firebase project for all five teammates. Firestore and Authentication must belong to this project.
2. Enable Firebase Authentication → Email/Password. Each person creates their own InTune account in the app. This account is separate from Spotify login. Email verification/password reset, account deletion, blocking/reporting, and abuse controls remain launch work, beyond this team prototype.
3. Create a Cloud Firestore **default database**. Do not deploy an open test-mode ruleset.
4. Register an app or obtain the Firebase project's public configuration. Put the project ID and **Web API key** into `InTune_442/CommunityConfig.json`. These identify the Firebase project; never add a service-account private key or admin credential to the iOS app. All teammates need this same config, plus independently allowlisted Spotify accounts for music import.
5. From `backend/`, install the test dependencies with `npm install`, then run `npm run test:rules` (Java required). The script uses the `demo-intune` emulator project, not production.
6. After rules tests and review pass, deploy the intended rules with `firebase deploy --only firestore:rules --project YOUR_PROJECT_ID`. Firebase deployment/login is the teammate's responsibility.
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
