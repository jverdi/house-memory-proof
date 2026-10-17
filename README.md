# House Memory — tiny native delivery proof

This is the source for a small iPhone app intended to prove delivery from this ChatGPT conversation through a managed macOS build runner to TestFlight. It is **not a compiled or delivered app yet**.

The app has a framing illustration toggle, a tap counter, and visible build/revision identifiers. It uses SwiftUI, supports iOS 18 and later, and has no external packages, camera access, sign-in, storage service, or network calls. The illustration is explicitly labeled; it does not reconstruct a house.

## Current evidence

The private repository `jverdi/house-memory-proof` has been created and the GitHub connection now has push access. The source and CI configuration passed local structural checks. Native compilation, simulator launch, signing, and TestFlight availability must still be verified from actual runs. Apple Developer membership and signing access have not yet been authorized.

## Continuation from ChatGPT on the iPhone

The agent should perform these engineering steps once the owner authorizes the required account access. The owner should not need to run shell commands or use a personal Mac.

1. Authorize the GitHub connection for the already-created private repository `jverdi/house-memory-proof` and its Actions workflows. Do not create a second repository or use the Adobe repositories. Check the available included Actions allowance before initiating billable usage.
2. Commit these files to `main`. The `simulator` job then compiles the actual iOS target, launches it on an iPhone simulator, and saves the build log and a screenshot. Retrieve and inspect that evidence; fix issues and rerun as necessary.
3. Use the secure Apple sign-in flow to verify active Apple Developer Program membership and the intended personal team. Enrollment, payments, legal terms, and account security challenges require the owner when applicable. No credentials belong in chat, source control, logs, or this archive.
4. Register a unique bundle identifier and create the corresponding App Store Connect app record. Choose the actual identifier after inspecting the personal team. The project uses `com.example.HouseMemoryProof` only as a simulator placeholder.
5. Configure an App Store Connect **team API key** with the permissions required for provisioning, cloud signing, and upload. Inspect the account's signing permissions first. Securely place it in repository secrets; do not print it. Creating that credential and granting persistent access requires the owner's explicit authorization at that step. No individual key is assumed because this workflow uses an issuer ID.
6. Configure the variables and secrets below, then set `ENABLE_TESTFLIGHT_UPLOAD=true`. Trigger the workflow on `main`. The upload job requires the simulator job to succeed first. Diagnose real failures from logs; do not silently substitute another Apple team or distribution method.
7. Inspect App Store Connect after upload. Wait for Apple processing, resolve any reported issues, and put the build in an internal testing group containing **only the owner**. Enable automatic distribution for subsequent builds if appropriate. The agent must verify availability, not just the upload command's exit status. Do not submit for public App Store release or invite other people.
8. The owner opens TestFlight and installs the build. Confirm that the displayed build/revision matches the cloud run and that the counter and framing toggle work. That is the end-to-end proof; a screenshot from the simulator alone is insufficient.

Apple's TestFlight Internal Only distribution avoids a public App Store release. It still requires an Apple Developer Program team. TestFlight builds are time-limited; this proof does not promise a permanent installation or silently schedule renewals.

## CI configuration

| Kind | Name | Purpose |
|---|---|---|
| Variable | `APPLE_TEAM_ID` | Actual 10-character personal Apple team ID |
| Variable | `APP_BUNDLE_ID` | Registered bundle ID matching the Apple app record |
| Variable | `ENABLE_TESTFLIGHT_UPLOAD` | `true` only after signing access and the app record are ready |
| Secret | `ASC_KEY_ID` | Team API key identifier |
| Secret | `ASC_ISSUER_ID` | API issuer UUID |
| Secret | `ASC_PRIVATE_KEY_P8` | Complete multiline private key, securely provisioned |

The workflow uses GitHub's standard `macos-26` runner and its selected Xcode. It records the exact Xcode version for each run. It uses Apple's `xcodebuild` directly; there is no Fastlane service, self-hosted runner, or app backend. Runner availability and account quotas must be verified when connected. The workflow's automatic signing is a candidate path that has not yet been exercised against this Apple account. A new team may need initial signing setup; any such work remains the agent's task, with owner authorization for credentials and agreements.

Upload happens only from `main`, after the simulator job succeeds and the upload variable is enabled. Pull requests cannot use the Apple secrets. Signing material is created in a temporary directory outside the checkout and removed on exit. Evidence artifacts include explicitly named logs, metadata, and screenshots, never the private key. Both workflows have bounded run times and do not run on a recurring schedule.

## What counts as proof

| Checkpoint | Required evidence | Initial status |
|---|---|---|
| Native compilation | Successful macOS `xcodebuild` log for the revision | Not run |
| Simulator launch | Successful launch log and inspected simulator screenshot | Not run |
| Signed archive | Successful archive/export logs for the actual Apple team | Not run |
| Apple acceptance | Uploaded build visible in App Store Connect | Not run |
| TestFlight readiness | Processed build assigned to the owner's internal group | Not run |
| Delivered to the phone | TestFlight installation and matching in-app build/revision | Not run |

`upload-result.json` intentionally marks processing, tester access, and device verification as unverified. A green upload job alone must not be reported as delivery.

## References checked during preparation

- [Apple: distribute apps using cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Apple: beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple: add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [GitHub-hosted runner images](https://github.com/actions/runner-images)

These references document the intended mechanism. They do not establish that this project has already built or that the connected accounts have the necessary permissions.
