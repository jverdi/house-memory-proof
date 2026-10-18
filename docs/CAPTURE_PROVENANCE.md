# Capture provenance contract

New camera observations carry optional, versioned `captureMetadata`. Older
archives remain readable; absence of this object means the information was not
recorded. It must not be reconstructed from a nearby photograph or a later
device clock.

The record distinguishes `rgbd_posed`, `rgb_posed` and `image_unregistered`.
High-resolution detail requests remain documentary. A camera calibration size
that differs from the encoded image size also downgrades the photograph to
documentary evidence. The original returned camera matrix is retained, but this
does not make a documentary photograph eligible for spatial processing.

`frameTimestamp` preserves `ARFrame.timestamp`. A separate receipt records UTC
bracketed by two host-uptime readings before image encoding. These are receipt
observations, not a measured camera-to-UTC transform. Transport delay and the
relationship between the frame and host clocks remain uncalibrated.

Rear-camera `ARDepthData` exposes no independent acquisition timestamp in this
adapter. `depthTimestamp` remains absent with an explicit reason. The
front-camera `capturedDepthDataTimestamp` is never substituted for scene depth.
No separate motion timestamp or calibrated lens-distortion model is invented.

The raw EXIF dictionary exposed by the returned frame is retained as a
content-addressed binary property-list asset, within a 256 KiB budget. It travels
with complete archives and incremental snapshots and is checked during capture
journal recovery, including idempotent retries. Unsupported or oversized EXIF
records produce an explicit unavailable reason while preserving the photograph.
The app does not equate ARCamera's renderer-oriented exposure controls with a
measured shutter time; available exposure information remains in the EXIF asset.

Depth copies accept only nonplanar `DepthFloat32` buffers with matching shape.
Confidence copies accept only matching `OneComponent8` buffers. Both validate
row stride, enforce a one-million-pixel bound, lock while copying and remove row
padding. No framework-owned base pointer escapes the copy. Invalid depth or
confidence buffers downgrade that capture to RGB-only evidence and preserve its
photograph, with a reason and revisit message. No nearby depth frame is used.

The saved image is encoded from the unrotated `capturedImage` buffer. The source
pixel format and calibration image dimensions are retained separately from the
JPEG asset; display orientation remains the observation's existing orientation
field. Device model and OS strings identify the capture environment but are not
a calibration certificate.

Depth fusion now requires a recorded confidence map. The defined medium and
high values retain their existing weights; absent and invalid values receive no
vote. Surface integration also checks the confidence and continuity of the
neighboring values used to seed and update a cell. Texture visibility requires
explicit high confidence. All these readers bound the declared depth/mask sizes
before loading them. The v16 derived-evidence fingerprint and v3 surface
checkpoint fingerprint prevent reuse under the older fallback contract.

Native regression requirements cover packed row contents, refusal of mismatched
shape/format/element width, receipt and unknown-clock validation, legacy decoding,
archive restoration, durable capture rows and corrupt EXIF journal recovery.
These checks do not establish physical timestamp accuracy, camera/depth alignment,
hardware identification, lens-mode transitions or sustained capture behavior.

API references checked October 18, 2026:

- [ARFrame timestamp](https://developer.apple.com/documentation/arkit/arframe/timestamp)
- [ARFrame EXIF data](https://developer.apple.com/documentation/arkit/arframe/exifdata)
- [ARCamera image resolution](https://developer.apple.com/documentation/arkit/arcamera/imageresolution)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)
- [ARCamera exposure duration](https://developer.apple.com/documentation/arkit/arcamera/exposureduration)
