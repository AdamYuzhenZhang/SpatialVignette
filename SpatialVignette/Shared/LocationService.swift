//
//  LocationService.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/9/25.
//

import Foundation
import CoreLocation

final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var completions: [(GPS?) -> Void] = []
    private var wantReverse = true
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func requestOneShot(withReverseGeocoding: Bool = true,
                        completion: @escaping (GPS?) -> Void) {
        completions.append(completion)
        wantReverse = withReverseGeocoding
        
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            flushAll(nil)
        @unknown default:
            flushAll(nil)
        }
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                flushAll(nil)
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let loc = locations.last else { flushAll(nil); return }

            guard wantReverse else {
                flushAll(GPS(location: loc))
                return
            }

            geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
                guard let self else { return }
                let address = Self.makeSingleLineAddress(from: placemarks?.first)
                self.flushAll(GPS(location: loc, address: address))
            }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            flushAll(nil)
        }

        private func flushAll(_ value: GPS?) {
            let cbs = completions
            completions.removeAll()
            cbs.forEach { $0(value) }
        }

        private static func makeSingleLineAddress(from p: CLPlacemark?) -> String? {
            guard let p else { return nil }
            // Simple, readable single-line format
            // "1 Infinite Loop, Cupertino, CA 95014, United States"
            var parts: [String] = []
            if let num = p.subThoroughfare, let street = p.thoroughfare {
                parts.append("\(num) \(street)")
            } else if let street = p.thoroughfare {
                parts.append(street)
            }
            if let city = p.locality { parts.append(city) }
            if let state = p.administrativeArea { parts.append(state) }
            if let zip = p.postalCode { parts.append(zip) }
            if let country = p.country { parts.append(country) }
            let line = parts.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
}
