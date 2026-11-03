# Firebase setup review — 2026-11-03

Work is isolated on `firebase-setup`, starting from main commit `047b6cc`. The existing Firebase project was created by the team; the reviewed rules were subsequently deployed with explicit approval as recorded below. Spotify source and configuration are unchanged.

## Existing implementation

| Area | Implemented behavior |
| --- | --- |
| Auth REST | Email/Password signup/sign-in through Identity Toolkit; refresh through Secure Token; Firebase ID token in Firestore Authorization headers. Passwords are not persisted. Sessions are saved to device-only Keychain. |
| Config | `FirebaseCommunityConfig.load()` decodes `CommunityConfig.json` from `Bundle.main`. The existing case-sensitive keys are `projectID` and `apiKey`. There is no Firebase Swift SDK dependency or `GoogleService-Info.plist` requirement for this REST integration. |
| Profiles | `profiles/{uid}` stores only `ownerID`, `name`, `age`, `bio`, `artists`, `genres`, `showcase`, `active`. Publishing/hiding is explicit. Discovery queries `active == true`. Existing match partners can read hidden profiles. |
| Swipes | `swipes/{fromUID}/outgoing/{toUID}` stores `fromID`, `toID`, `decision`, `createdAt`. Sender owns writes/listing. Sender and recipient can get an individual swipe; unrelated users cannot. Recipient access is needed for the existing mutual-like REST flow. |
| Matches | `matches/{matchID}` stores `members` and `createdAt`. Two active profiles and two stored likes are required. Swift sorts the two UIDs and joins them with `__`. Refresh reconciles interrupted match creation; concurrent create conflicts are recovered through a membership query. |
| Messaging | `matches/{matchID}/messages/{messageID}` stores `senderID`, `text`, `sentAt`. Members can read/create; authenticated UID must equal sender. Matches and messages cannot be edited/deleted through these rules. |
| Backend directory | Firestore rules, local emulator config and Node tests. No Cloud Function, custom API server, or automatic server-side match trigger. Tests use only `demo-intune` and localhost port 8189. |

The public profile serializer does not include emails, Spotify account identifiers, OAuth tokens, passwords, or private credentials. Account email goes to Authentication only. User-entered public strings can still contain whatever users type; field allowlists do not redact text. Cloud documents have not been inspected; the deployed rules were read back and verified after approved deployment.

## Configuration and validation log

- Created `firebase-setup` from a clean main checkout.
- Set `projectID` to the user-supplied `intune-6ce55` and `apiKey` to the user-supplied **public Firebase Web API key** in the existing JSON file. No other configuration file or collection/field name was introduced.
- Node.js 22.23.4/npm and Java 27 are available. Added ignores for `backend/node_modules/` and emulator debug logs. Generated the npm lockfile for repeatable installation.
- Initial sandboxed install hit native build restrictions; completed npm installation outside the sandbox. `npm audit` reports 29 development dependency vulnerabilities (17 moderate, 11 high, 1 critical), including a critical transitive `tar` advisory in the CLI dependency tree. Its suggested CLI fix is a major upgrade to firebase-tools 15; SDK fixes suggested by audit also cross major versions. No automatic upgrades/overrides were applied. These npm packages are local test tooling, not dependencies embedded in the iOS app.
- Initial sandboxed emulator attempt could not bind a local port. This was an environment failure before any security assertions, not a failing rules test. Subsequent runs outside the sandbox succeeded.
- Original `npm run test:rules`: **6/6 PASS** (`/tmp/intune-rules-baseline.log`). Expanded regression suite before the rules fix: **12/13 PASS**, one expected regression failure: a nested credential-shaped object inside `artists` was accepted (`/tmp/intune-rules-expanded-before.log`).
- Fixed artist/genre entry validation to require strings at each permitted position, including empty and maximum-sized lists. This enforces the existing Swift contract without changing paths, fields, or limits.
- Final `npm run test:rules`: **13/13 PASS**, zero failures (`/tmp/intune-rules-final.log`). Covers owner profile create/update/delete, credential-field rejection, every artist/genre list position, unauthenticated and unrelated swipe access, recipient get versus sender-only listing, self-swipes, reciprocal likes versus passes, inactive profiles, malformed matches, membership queries, immutable matches/messages, sender spoofing, private message lists, timestamps, message limits, and hidden-profile/chat continuity.
- iOS simulator Debug build with `CODE_SIGNING_ALLOWED=NO`: **PASS**. `/tmp/intune-firebase-ios-build.log` contains the build output.
- Checked the newly built app's `CommunityConfig.json` against the source JSON: **PASS**, exact match, expected project ID, correct keys and nonempty key. The Xcode synchronized app folder includes the JSON as a resource; the Swift loader uses that same resource name. No key value is printed in verification output.
- Executed the actual `FirebaseCommunityConfig.load()` implementation in a temporary macOS test bundle containing the config copied from the iOS build: **PASS**, correct project ID and configured state. This validates resource lookup/Swift decoding separately from a live Firebase connection; no app source changes were needed for the probe.
- Existing Swift REST/model checks: **PASS** for config validation, deterministic IDs, public field allowlist, codecs, authenticated requests, server timestamps/create-only preconditions, missing/empty results, and sign-out. The host compiler needed an explicit macOS SDK/target; this was unrelated to the successful iOS build.
- Source startup review: Firebase client initialization reads config and Keychain only; community refresh returns immediately when there is no signed-in UID. Missing Firebase config does not itself explain the reported black launch screen. Runtime attempt: iPhone 17 Pro boot completed in 29 seconds and a screenshot showed the normal iOS home screen, but app installation stalled before the launch command completed. Interrupted the attempt; full UI launch and the original black-screen cause remain unverified.
- `git diff --check`: **PASS**.
- Final rules review: no critical authorization bypass identified in the reviewed rules. `backend/firebase.json` resolves `firestore.rules` to the exact file loaded by the tests; rules/test files are unchanged since the 13/13 passing run. Rules SHA-256: `4d8cfba06bde52e5230d1b69dd5e9a502d6712f0045193f4ef3935fe127e570d`. Unmatched paths have no allow rule. Duplicate reverse-order match IDs remain a noncritical integrity limitation; they do not bypass mutual likes or membership checks. No rules/schema changes or deployment were made during this final review.
- With subsequent explicit approval, deployed **only Firestore rules** to `intune-6ce55` on November 3, 2026, at 3:31 PM America/New_York. Firebase reported successful compilation and release. Read back `projects/intune-6ce55/releases/cloud.firestore`, ruleset `2450d6e8-fb05-43f6-a9de-4db68936e973`, and verified exact source equality and the reviewed SHA-256 above. No database documents/schema or other Firebase services were deployed.

## Remaining checks and future deployments

1. The rule changes passed review and emulator tests, and the approved rules deployment is verified. Adding an API key alone does not publish rules; future rule changes still require testing and approval.
2. The user confirms the Firebase API key restrictions have been verified and are compatible with the current REST integration. No additional key/config change was made during final review.
3. The user reports Email/Password enabled and the `(default)` Firestore database created; these cloud settings have not been independently verified. Do not create another project. All five teammates use this same project/config and separate InTune accounts; Console IAM membership is separate from app accounts.
4. Obtain explicit approval before any production rules publication. No `firebase init`, login, or deploy is needed for the demo emulator tests.
5. After approved deployment, run the README two-device acceptance check using real accounts: both publish, one like creates no match, reciprocal likes create a shared match, messages survive relaunch, hiding preserves existing chat. Use a third account to verify chat/swipe denial.
6. Review development dependency audit findings before sharing the tooling setup. Before a public launch, password reset/email verification/account deletion, blocking/reporting, abuse controls, App Check support, and polling/read costs remain separate work. These are not implemented by this setup branch.
7. The Spotify handoff already records a previously committed client secret. Its owner should confirm rotation; current source uses public client ID/PKCE and no client secret. No Spotify code is changed here.

Known prototype limits: discovery/match queries cap at 100 documents; chats and matches poll rather than use realtime listeners. Rules accept either UID ordering for a match ID while Swift always uses sorted order, so the rules do not by themselves enforce a unique canonical match document for a pair. Hiding a profile does not revoke existing chat access, and signing out does not hide a published profile.

References: [Firebase API keys](https://firebase.google.com/docs/projects/api-keys), [REST authentication and rules](https://firebase.google.com/docs/firestore/use-rest-api), [Rules tests](https://firebase.google.com/docs/rules/unit-tests).
