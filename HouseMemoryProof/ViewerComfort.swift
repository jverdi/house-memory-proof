import SwiftUI

// Viewer preferences are local to this installation. They never alter camera
// calibration, source poses, geometry, measurements or exported records.
struct ViewerComfort: Codable, Equatable {
  var speed = 1.3
  var acceleration = 2.5
  var turnDegreesPerSecond = 90.0
  var sensitivity = 1.0
  var fieldOfView = 60.0
  var eyeHeight = 1.7
  var invertY = false
  var leftHanded = false

  var bounded: ViewerComfort {
    var result = self
    func bound(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
      value.isFinite ? max(range.lowerBound, min(range.upperBound, value)) : fallback
    }
    result.speed = bound(speed, 0.2...2, 1.3)
    result.acceleration = bound(acceleration, 0.2...4, 2.5)
    result.turnDegreesPerSecond = bound(turnDegreesPerSecond, 30...180, 90)
    result.sensitivity = bound(sensitivity, 0.25...2, 1)
    result.fieldOfView = bound(fieldOfView, 45...90, 60)
    result.eyeHeight = bound(eyeHeight, 0.8...2.2, 1.7)
    return result
  }
  static func decode(_ text: String) -> ViewerComfort {
    guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
    return value.bounded
  }
  var encoded: String {
    guard let data = try? JSONEncoder().encode(bounded) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
}

struct ViewerComfortSettings: View {
  @Binding var settings: ViewerComfort
  var body: some View {
    Form {
      Section {
        Text("Make the 3D view comfortable to explore. These choices are remembered on this iPhone and do not change your photos or house record.")
      }
      Section("Movement") {
        control("Walking speed", value: $settings.speed, range: 0.2...2, step: 0.1, unit: "m/s", digits: 1, id: "viewer-speed")
        control("Build up speed", value: $settings.acceleration, range: 0.2...4, step: 0.1, unit: "m/s²", digits: 1, id: "viewer-acceleration")
        Text("A lower build-up setting starts more gently. Releasing the control always stops movement immediately. Step buttons still move 20 cm per tap.").font(.footnote)
      }
      Section("Looking around") {
        control("Turning speed", value: $settings.turnDegreesPerSecond, range: 30...180, step: 15, unit: "°/s", digits: 0, id: "viewer-turn-speed")
        control("Drag sensitivity", value: $settings.sensitivity, range: 0.25...2, step: 0.25, unit: "×", digits: 2, id: "viewer-sensitivity")
        Toggle("Reverse up and down looking", isOn: $settings.invertY).accessibilityIdentifier("viewer-invert-y")
        Toggle("Left-handed layout", isOn: $settings.leftHanded).accessibilityIdentifier("viewer-left-handed")
        Text("Left-handed layout puts movement on the right so your left hand can drag the scene to look. Turning speed also limits fast drags. The named look buttons keep their usual direction.").font(.footnote)
      }
      Section("View") {
        control("View width", value: $settings.fieldOfView, range: 45...90, step: 5, unit: "°", digits: 0, id: "viewer-field-of-view")
        control("Eye height", value: $settings.eyeHeight, range: 0.8...2.2, step: 0.1, unit: "m", digits: 1, id: "viewer-eye-height")
        Text("A wider view shows more at once. Eye height starts at 1.7 m and applies when walking on a captured floor. If there is not enough space for that view, the app finds a checked viewpoint or enables Free fly. It never removes an obstacle.").font(.footnote)
      }
      Section {
        Button("Reset movement and view") { settings = ViewerComfort() }.accessibilityIdentifier("viewer-reset-settings")
        Text("Reset restores these settings only. Your records and saved viewpoints stay as they are.").font(.footnote)
      }
    }.navigationTitle("Movement & view")
  }
  private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, digits: Int, id: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(title): \(value.wrappedValue.formatted(.number.precision(.fractionLength(digits)))) \(unit)")
      // Keep the native adjustable value so accessibility clients can operate
      // the slider consistently. Include the meaningful units in its label.
      Slider(value: value, in: range, step: step)
        .accessibilityLabel("\(title): \(value.wrappedValue.formatted(.number.precision(.fractionLength(digits)))) \(unit)")
        .accessibilityIdentifier(id)
    }
  }
}
