import MapKit
import SwiftUI

/// Kaartje bij het adres van een afspraak, met een schatting van de reistijd per auto vanaf kantoor of thuis.
struct EventLocationView: View {
    let location: String
    /// Aankomst: het begin van de afspraak.
    let arrival: Date

    private enum Origin: String, CaseIterable, Identifiable {
        case office = "Kantoor", home = "Thuis"
        var id: String { rawValue }
    }

    @AppStorage(SettingsKey.officeAddress) private var officeAddress = AppSettings.defaultOfficeAddress
    @AppStorage(SettingsKey.homeAddress) private var homeAddress = ""

    @State private var origin: Origin = .office
    @State private var destination: MKMapItem?
    @State private var position: MapCameraPosition = .automatic
    @State private var travel: (time: TimeInterval, distance: CLLocationDistance)?
    @State private var note: String?
    @State private var isWorking = true

    private struct TravelKey: Equatable {
        var origin: String
        var address: String
        var destinationFound: Bool
    }

    private var originAddress: String { origin == .office ? officeAddress : homeAddress }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let destination {
                Map(position: $position) {
                    Marker(location, coordinate: destination.placemark.coordinate)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        destination.openInMaps()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Open in Kaarten")
                }
            } else if isWorking {
                ProgressView().controlSize(.small)
            }

            Picker("Vanaf", selection: $origin) {
                ForEach(Origin.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200)

            if let travel {
                let departure = arrival.addingTimeInterval(-travel.time)
                Text("Per auto \(Self.duration(travel.time)) (\(Int((travel.distance / 1000).rounded())) km) vanaf \(origin.rawValue.lowercased()) · vertrek rond \(DutchDate.time(departure))")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
            } else if let note {
                Text(note).thingsFont(.metadata).foregroundStyle(ThingsColor.textTertiary)
            }
        }
        .task(id: location) {
            isWorking = true
            destination = await Self.mapItem(for: location)
            if let destination {
                position = .region(MKCoordinateRegion(center: destination.placemark.coordinate,
                                                      latitudinalMeters: 2500, longitudinalMeters: 2500))
            } else {
                note = "Dit adres is niet gevonden in Kaarten."
            }
            isWorking = false
        }
        .task(id: TravelKey(origin: origin.rawValue, address: originAddress, destinationFound: destination != nil)) {
            await estimate()
        }
    }

    private func estimate() async {
        travel = nil
        guard let destination else { return }
        let address = originAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            note = "Vul het adres van \(origin.rawValue.lowercased()) in bij Voorkeuren › Agenda's."
            return
        }
        guard let source = await Self.mapItem(for: address) else {
            note = "Het adres van \(origin.rawValue.lowercased()) is niet gevonden."
            return
        }
        note = nil
        var request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile
        if arrival > .now { request.arrivalDate = arrival }
        do {
            let response = try await MKDirections(request: request).calculateETA()
            travel = (response.expectedTravelTime, response.distance)
        } catch {
            // Verkeer voor een tijdstip dat Kaarten (nog) niet kent: opnieuw zonder tijdstip.
            request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = .automobile
            if let response = try? await MKDirections(request: request).calculateETA() {
                travel = (response.expectedTravelTime, response.distance)
            } else {
                note = "Reistijd kon niet worden berekend."
            }
        }
    }

    private static func mapItem(for address: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        // Voorkeur voor Nederland.
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 52.1, longitude: 5.3),
                                            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) u \(minutes % 60) min"
    }
}
