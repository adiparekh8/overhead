import CoreLocation
import OverheadCore

/// Wraps CoreLocation. All callbacks arrive on the main thread.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case waiting      // not asked yet, or no fix yet
        case authorized
        case denied
        case unavailable  // Location Services are off, or the fix failed
    }

    private let manager = CLLocationManager()
    private(set) var status: Status = .waiting
    private(set) var coordinate: Coordinate?
    var onChange: (() -> Void)?

    func start() {
        manager.delegate = self
        // A kilometre is plenty for "what is above me", and uses less power.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 500
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        refreshStatus()
        manager.startUpdatingLocation()
    }

    private func refreshStatus() {
        let new: Status
        switch manager.authorizationStatus {
        case .notDetermined: new = .waiting
        case .restricted, .denied: new = .denied
        default: new = .authorized
        }
        if new != status {
            status = new
            if new == .denied { coordinate = nil }
            onChange?()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshStatus()
        if status == .authorized { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let new = Coordinate(
            latitude: latest.coordinate.latitude,
            longitude: latest.coordinate.longitude
        )
        guard new.isValid else { return }
        coordinate = new
        status = .authorized
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        if code == .denied {
            status = .denied
            coordinate = nil
        } else if coordinate == nil {
            // "Location unknown" is temporary; CoreLocation keeps trying.
            status = code == .locationUnknown ? .waiting : .unavailable
        }
        onChange?()
    }
}
