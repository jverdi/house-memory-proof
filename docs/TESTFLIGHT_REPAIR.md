# Requested homeowner TestFlight snapshot repair

Status: prepared for complete validation and upload. No Apple upload or availability is claimed.

The owner requested a new TestFlight snapshot and directed continued implementation in the current thread on 18 October 2026 New York time. The first delivery attempt, 228.1 / f7123ca2ee6c556620b3f01cc3d6d88bc20d0597, passed Debug/Release compilation, all 182 native checks, 19 reader phases, 52 command contracts, 36 export reports, 50 portable checks and three process recoveries. Seventeen interface workflows passed; two failed. Apple upload was skipped. Both artifact hashes and both failure recordings are independently checked in [the retained evidence](evidence/native-f712-summary.json).

The envelope editor shared one Boolean focus binding across four fields. The evidence-field Done action left the keyboard over the confirmation control. Distinct field identities and explicit responder dismissal now make Done close that keyboard. The interface workflow additionally requires the keyboard to disappear after both numeric and evidence entry before checking confirmation and saved persistence.

The comfort test's normalized slider gesture stopped at 1.0 m instead of the required 0.8 m. Its controls retain their meaningful spoken numeric values and units. The test now drags from the displayed value to each endpoint and asserts the same required numeric values. No setting bound or acceptance threshold changes. Repeated accessibility existence queries within a single scroll step are removed while retaining visibility, reachability and time bounds.

The repair is isolated on requested-snapshot-20261019, based on the requested f712 source. The exact release marker admits this one replacement snapshot only after the full existing simulator job passes. The native count remains 182 and all 19 interface workflows remain mandatory; the 300-second native, 2,100-second interface and 60-minute job limits are unchanged. The accepted personal-beta tag and final renewal gate are unchanged. This branch excludes subsequent map summaries, distant-room handoff and prepared streaming/render-origin changes, which continue through their own validation.

Once signing/upload and exact-build Apple processing and Personal iPhone owner access are verified, record the replacement build and evidence here. Precision, whole-house acceptance and physical-device/field qualification remain open.

The later 230.1 validation exposed the same keyboard dismissal failure in batch classification. This repair also explicitly resigns that editor’s filter responder for toolbar Done and keyboard submission. The existing keyboard-disappearance assertion remains mandatory. This additional repair is not yet simulator-validated.
