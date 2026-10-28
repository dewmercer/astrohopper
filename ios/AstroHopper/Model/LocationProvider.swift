import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Defaults match the web app until the first fix; the last fix is remembered
    /// so the sky is right at startup even before GPS answers.
    private(set) var latitude: Double
    private(set) var longitude: Double
    private(set) var hasFix = false
    private(set) var authorized = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults = UserDefaults.standard

    override init() {
        latitude = defaults.object(forKey: "last_lat") as? Double ?? 31.9
        longitude = defaults.object(forKey: "last_lon") as? Double ?? 34.8
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorized = true
            manager.startUpdatingLocation()
        default:
            authorized = false
        }
    }

    func refresh() {
        if authorized { manager.requestLocation() } else { start() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { start() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        MainActor.assumeIsolated {
            latitude = c.latitude
            longitude = c.longitude
            hasFix = true
            defaults.set(c.latitude, forKey: "last_lat")
            defaults.set(c.longitude, forKey: "last_lon")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
