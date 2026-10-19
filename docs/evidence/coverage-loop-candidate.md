# Bounded coverage-response loop candidate

Prepared after the saved-viewpoint recovery candidate. Native execution is pending. This adds one native check, bringing the combined expected total to 181 with all 19 interface workflows retained.

Runbook §§9.5 and 20.5 require the application to request another view and a simulated operator to respond with delay, imperfect compliance and movement limits. The existing advice checks tested fixed input batches. This continuation extracts the app's existing next-gap selection into `BoundaryCoverageReport.nextGap(after:)`, shared by the wall/ceiling interface and the bounded replay.

Five disclosed analytic wall cases repeatedly run the actual coverage analyzer, obtain its next patch and advice, and supply the operator's next observation. A responsive operator translates by at most 16 cm per request; a delayed operator moves at most 8 cm, waits two ticks, and misses every third instruction. A constrained operator cannot travel far enough to establish the required angle. A foreground obstruction has no accessible alternate view. A sensor fault continues to supply no depth. Each case stops within 64 ticks and 16 saved photographs, with no automatic retry beyond that cap.

The retained aggregate trace records requested patch/advice, operator action, capture effort, waiting/missed instructions, supported patches and remaining gaps. The constrained and faulty cases must retain all gaps with zero false completeness. Successful cases still need the existing three separated views and angular/depth/quality checks. Geometry, thresholds and source records are not repaired by the operator.

This is a disclosed single-plane development diagnostic in the native test process. It is not an independently isolated oracle evaluation, continuous whole-house simulation, live ARSession replay, semantic completeness, physical accuracy or field qualification. The broad diversity and protected evaluation gates remain open. No localization variant or exhausted repair-budget experiment is executed.

The report is `native-coverage-loop.json`; only aggregate requests and counters are published. Camera poses, images and source geometry remain private. Native/interface execution bounds and 19 reader phases, 52 command contracts and 36 independent export reports remain unchanged.
