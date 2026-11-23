import AppKit
import OverheadCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Search") {
                LabeledContent("Radius") {
                    HStack {
                        Slider(value: $model.radiusNM, in: 5...50, step: 5)
                            .frame(width: 180)
                        Text(Format.distance(nm: model.radiusNM, unit: model.speedUnit))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("Fly aircraft across the top of the screen", isOn: $model.flyoverEnabled)
                LabeledContent("When closer than") {
                    HStack {
                        Slider(value: $model.flyoverRangeNM, in: 1...15, step: 1)
                            .frame(width: 180)
                        Text(Format.distance(nm: model.flyoverRangeNM, unit: model.speedUnit))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!model.flyoverEnabled)
                Button("Preview") { model.previewFlyover() }
            } header: {
                Text("Flyover")
            } footer: {
                Text("Each aircraft is shown once, flying in the direction it is actually heading. Clicks pass through it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Units") {
                Picker("Altitude", selection: $model.altitudeUnit) {
                    Text("Feet").tag(AltitudeUnit.feet)
                    Text("Meters").tag(AltitudeUnit.meters)
                }
                .pickerStyle(.segmented)
                Picker("Speed and distance", selection: $model.speedUnit) {
                    Text("kt · nm").tag(SpeedUnit.knots)
                    Text("mph · mi").tag(SpeedUnit.mph)
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Mac's location") {
                    Text(locationStatusText)
                        .foregroundStyle(.secondary)
                }
                if model.locationStatus == .denied {
                    Button("Open Location Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Toggle("Always use a manual location", isOn: $model.useManualLocation)
                TextField("Latitude", text: $model.manualLatitude, prompt: Text("40.6413"))
                TextField("Longitude", text: $model.manualLongitude, prompt: Text("-73.7781"))
                if let problem = manualLocationProblem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Location")
            } footer: {
                Text("The manual location is used when it is switched on, or whenever the Mac's location is not available. Only a rounded position (about 1 km) is sent to ADSB.lol.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("FAA registry") {
                    Text(model.registryAvailable
                         ? "Built \(model.registryBuiltDate ?? "on an unknown date")"
                         : "Not found. Run build_db.py")
                        .foregroundStyle(model.registryAvailable ? Color.secondary : Color.red)
                }
                LabeledContent("Aircraft positions") {
                    Link("ADSB.lol (ODbL)", destination: URL(string: "https://www.adsb.lol")!)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Positions refresh every 10 seconds while the card is open. In the background Overhead paces itself to ADSB.lol's daily request limit, about every 3 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var locationStatusText: String {
        switch model.locationStatus {
        case .authorized: return model.deviceLocation == nil ? "Waiting for a fix…" : "Available"
        case .denied: return "Access denied"
        case .unavailable: return "Unavailable"
        case .waiting: return "Waiting…"
        }
    }

    private var manualLocationProblem: String? {
        let lat = model.manualLatitude.trimmingCharacters(in: .whitespaces)
        let lon = model.manualLongitude.trimmingCharacters(in: .whitespaces)
        if lat.isEmpty && lon.isEmpty {
            return model.useManualLocation ? "Enter a latitude and longitude." : nil
        }
        if model.manualCoordinate == nil {
            return "Latitude must be between -90 and 90, longitude between -180 and 180."
        }
        return nil
    }
}
