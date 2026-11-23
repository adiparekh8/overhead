import AppKit
import OverheadCore
import SwiftUI

/// The dark, translucent backing of the card.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Reports whether the window holding the card is actually on screen.
/// SwiftUI's onAppear is not enough: a menu bar extra builds its content
/// before the user ever opens it.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let window {
                let names: [Notification.Name] = [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didResignKeyNotification,
                    NSWindow.willCloseNotification,
                ]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                        self?.report(closing: note.name == NSWindow.willCloseNotification)
                    }
                }
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            let visible = !closing && (window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

struct CardView: View {
    let model: AppModel
    /// Off for still snapshots.
    var animated = true

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let overhead = model.overhead {
                header(overhead)
                    .id(overhead.id)
                    .transition(.blurReplace)
                divider
                owner(overhead)
                    .id("owner-" + overhead.id)
                    .transition(.opacity)
                divider
                stats(overhead)
                divider
                radar
                if model.nearby.count > 1 {
                    divider
                    nextClosest
                }
            } else {
                emptyState
                divider
                radar
            }
            divider
            footer
        }
        .frame(width: 320)
        .background { if animated { GlassBackground() } }
        .environment(\.colorScheme, .dark)
        .animation(animated ? .smooth(duration: 0.4) : nil, value: model.overhead?.id)
        .background {
            if animated {
                WindowVisibilityReader { visible in model.setCardOpen(visible) }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: Header

    private func header(_ item: OverheadAircraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.tailNumber)
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let callsign = item.aircraft.callsign, callsign != item.tailNumber {
                    Text(callsign)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                        .help("Callsign")
                }
            }
            Text(item.typeLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Owner

    @ViewBuilder
    private func owner(_ item: OverheadAircraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("REGISTERED OWNER")
            if !model.registryAvailable {
                Text("FAA database not found")
                    .font(.system(size: 15, weight: .semibold))
                Text("Run build_db.py to see who aircraft are registered to.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let record = item.record {
                Text(record.owner.isEmpty ? "Owner not listed" : record.ownerDisplay)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                let detail = [record.registrantType, record.place].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if !record.owner.isEmpty, record.ownerIsCompanyOrTrustee {
                    Label {
                        Text("The registered owner may not be the person who uses this aircraft.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                }
            } else {
                Text("Not in the FAA registry")
                    .font(.system(size: 15, weight: .semibold))
                Text("Registered outside the US, or not listed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Stats

    private func stats(_ item: OverheadAircraft) -> some View {
        let trend = VerticalTrend(feetPerMinute: item.aircraft.verticalRate)
        return HStack(alignment: .top, spacing: 0) {
            stat("ALTITUDE") {
                HStack(spacing: 4) {
                    value(Format.altitudeValue(feet: item.nearby.altitudeFeet, unit: model.altitudeUnit), model.altitudeUnit.label)
                    if trend != .level {
                        Image(systemName: trend == .climbing ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(trend == .climbing ? "climbing" : "descending")
                    }
                }
            }
            stat("SPEED") {
                if let gs = item.aircraft.gs {
                    value(Format.speedValue(knots: gs, unit: model.speedUnit), model.speedUnit.label)
                } else {
                    value("—", "")
                }
            }
            stat("DISTANCE") {
                HStack(spacing: 4) {
                    value(Format.distanceValue(nm: item.nearby.slantNM, unit: model.speedUnit), model.speedUnit.distanceLabel)
                    Text(Format.compass(item.nearby.bearing))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stat(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(_ number: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(animated ? .smooth(duration: 0.3) : nil, value: number)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    // MARK: Radar

    private var radar: some View {
        HStack {
            Spacer()
            RadarView(
                aircraft: model.nearby,
                highlightedID: model.overhead?.id,
                radiusNM: model.radiusNM,
                animated: animated && model.cardOpen
            )
            .frame(width: 168, height: 168)
            .overlay(alignment: .bottomTrailing) {
                Text(Format.distance(nm: model.radiusNM, unit: model.speedUnit))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .offset(x: 22, y: 2)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: Next closest

    private var nextClosest: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("NEXT CLOSEST")
            ForEach(model.nearby.dropFirst().prefix(3)) { plane in
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees((plane.aircraft.heading ?? 90) - 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(plane.aircraft.registration ?? plane.aircraft.callsign ?? plane.aircraft.hex.uppercased())
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    if let type = plane.aircraft.typeCode {
                        Text(type)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(Format.altitude(feet: plane.altitudeFeet, unit: model.altitudeUnit))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(Format.distance(nm: plane.slantNM, unit: model.speedUnit))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Empty state

    private var emptyState: some View {
        let (title, detail): (String, String) = {
            if model.effectiveLocation == nil {
                switch model.locationStatus {
                case .denied:
                    return ("Location is off", "Allow location access, or enter a latitude and longitude in Settings.")
                case .unavailable:
                    return ("Location unavailable", "Enter a latitude and longitude in Settings.")
                default:
                    return ("Finding your location", "You can also enter one in Settings.")
                }
            }
            switch model.fetchState {
            case .idle:
                return ("Looking up", "Checking for aircraft near you.")
            case .quotaReached:
                return ("Daily limit reached", "ADSB.lol allows a set number of requests per day. Overhead will resume by itself.")
            case .failed(let message) where model.lastUpdate == nil:
                return ("Can't reach ADSB.lol", message)
            default:
                let range = Format.distance(nm: model.radiusNM, unit: model.speedUnit)
                return ("Clear skies", "No aircraft in the air within \(range).")
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if animated && model.cardOpen {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    statusText(now: timeline.date)
                }
            } else {
                statusText(now: Date())
            }
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Overhead")
            .accessibilityLabel("Quit Overhead")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func statusText(now: Date) -> some View {
        let text: String = {
            switch model.fetchState {
            case .failed where model.lastUpdate != nil: return "Connection problem · retrying"
            case .quotaReached: return "Daily request limit reached"
            default: break
            }
            guard let last = model.lastUpdate else { return "" }
            let age = Int(max(0, now.timeIntervalSince(last)))
            let ago = age < 5 ? "Updated just now" : age < 60 ? "Updated \(age)s ago" : "Updated \(age / 60)m ago"
            return model.isUsingManualLocation ? ago + " · manual location" : ago
        }()
        return Text(text)
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}
