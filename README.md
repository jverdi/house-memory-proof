# House Xray — native iPhone delivery proof

**Delivered and installed successfully on the owner's iPhone on October 17, 2026.**

This tiny SwiftUI app proves the delivery path from ChatGPT Mobile through a private GitHub repository, a hosted macOS runner, Apple signing, and internal TestFlight distribution. No personal Mac, self-hosted runner, or app backend was required.

The proof app contains a framing illustration toggle, tap counter, and build/revision identifiers. It supports iOS 18 and later. It does not capture or reconstruct a house.

## Verified evidence

- [Build and upload run](https://github.com/jverdi/house-memory-proof/actions/runs/39001729914): simulator compilation and launch, signed archive, and successful Apple upload.
- Build **2.1**, source revision **826c2fbad4**.
- [TestFlight readiness](https://github.com/jverdi/house-memory-proof/actions/runs/39002137648): Apple processing **VALID**, internal state **IN_BETA_TESTING**, owner membership verified in **Personal iPhone**.
- Owner confirmed receiving and successfully installing the app at **2026-10-17 00:20 EDT**.
- [Machine-readable delivery evidence](docs/evidence/testflight-delivery-2.1.json).
- Physical-device interaction tests and an independently read device build number have not been verified.

## Delivery configuration

App Store Connect name: **House Xray**  
App ID: **6823862609**  
Bundle ID: **com.jverdi.housememoryproof**  
Apple team: **4RLZ6F3UA4**

Repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_P8`. Credentials remain in GitHub secrets and ephemeral runner files, never evidence or source.

The native workflow builds relevant source changes on `main`, verifies simulator launch, and signs/uploads using Xcode on `macos-26`. Team and bundle values have verified defaults; repository variables can override them. Set `ENABLE_TESTFLIGHT_UPLOAD=false` to disable uploads. Pull requests do not run the upload job.

The readiness workflow runs after successful native delivery, polls Apple processing for up to ten minutes, and assigns valid builds to the uniquely verified owner's internal testing group. It does not invite other people or publish to the App Store. It records status without account email addresses.

The original Apple credential setup and app-record creation required owner interaction. Subsequent source-to-TestFlight delivery is automated, subject to Apple processing, account permissions, runner availability, and quotas. TestFlight builds expire; no scheduled renewal has been configured.

## Scope

This completes the delivery experiment, not the house-scanning application. Capture, reconstruction, AR alignment, drawings, measurement, labeling, walkthroughs, and exports remain the larger project's implementation work.
