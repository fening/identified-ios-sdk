#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `DigitalAddressField.tsx` without the map. Resolves a typed code, or
/// encodes the device's location, and asks the subject to confirm the place.
struct AddressStepView: View {
    /// Called with the confirmed address, and whether the lookup was unavailable.
    let confirmed: (StatedAddress, Bool) -> Void
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var candidate: (address: DigitalAddress, source: AddressSource)?
    @State private var locator = LocationFetcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("poa.address.prompt")).font(theme.heading(20)).foregroundStyle(theme.palette.textPrimary)
            if let candidate {
                confirm(candidate.address, source: candidate.source)
            } else {
                entry
            }
            if let error { ErrorText(message: error) }
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldBox(label: L10n.string("poa.address.label")) {
                MaskedTextField(placeholder: "GA-183-9124", text: $code, mask: DigitalAddressCode.mask)
            }
            BodyText(L10n.string("poa.address.helper"), secondary: true, size: 13)
            PrimaryButton(title: L10n.string("poa.address.find"), busyTitle: L10n.string("poa.address.checking"), busy: busy,
                          enabled: DigitalAddressCode.isValid(code)) {
                Task { await resolve() }
            }
            HStack {
                Rectangle().fill(theme.palette.border).frame(height: 1)
                Text(L10n.string("poa.address.unknown")).font(theme.body(13)).foregroundStyle(theme.palette.textSecondary).fixedSize()
                Rectangle().fill(theme.palette.border).frame(height: 1)
            }
            SecondaryButton(title: L10n.string("poa.address.location"), enabled: !busy) { Task { await locate() } }
                .accessibilityLabel(L10n.string("poa.address.location_label"))
            BodyText(L10n.string("poa.address.footnote"), secondary: true, size: 13)
        }
    }

    private func confirm(_ address: DigitalAddress, source: AddressSource) -> some View {
        let place = DigitalAddressCode.describe(address)
        return Card {
            Text(L10n.string("poa.address.confirm").uppercased()).font(theme.body(11, weight: .medium)).tracking(1.3).foregroundStyle(theme.palette.textSecondary)
            Text(DigitalAddressCode.displayForm(address.code)).font(theme.heading(18)).foregroundStyle(theme.palette.textPrimary)
            BodyText(place.isEmpty ? L10n.string("poa.address.no_locality") : place, size: 15)
            if let street = address.street, !street.isEmpty { BodyText(street, secondary: true, size: 14) }
            HStack(spacing: 10) {
                SecondaryButton(title: L10n.string("poa.address.change_it")) {
                    candidate = nil
                    code = ""
                }
                PrimaryButton(title: L10n.string("poa.address.right")) {
                    confirmed(stated(address, source: source), false)
                }
            }
        }
    }

    private func stated(_ address: DigitalAddress, source: AddressSource) -> StatedAddress {
        let normalised = DigitalAddressCode.storageForm(address.code)
        return StatedAddress(code: normalised.isEmpty ? address.code.uppercased().replacingOccurrences(of: "-", with: "") : normalised,
                             area: address.area, district: address.district, region: address.region, source: source)
    }

    private func resolve() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            candidate = (try await flow.client.resolveDigitalAddress(code: DigitalAddressCode.storageForm(code)), .typed)
        } catch APIError.http(503, _) {
            // Lookup unavailable: take the code as typed and say so.
            confirmed(StatedAddress(code: DigitalAddressCode.storageForm(code), source: .typed), true)
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("poa.address.not_found")
        }
    }

    private func locate() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let point = try await locator.current()
            candidate = (try await flow.client.encodeDigitalAddress(latitude: point.latitude, longitude: point.longitude), .currentLocation)
        } catch let problem as LocationProblem {
            error = switch problem {
            case .unavailable: L10n.string("poa.location.unavailable")
            case .denied: L10n.string("poa.location.denied")
            case .timeout: L10n.string("poa.location.timeout")
            case .failed: L10n.string("poa.location.failed")
            }
        } catch APIError.http(404, _) {
            error = L10n.string("poa.address.no_code")
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("poa.address.lookup_failed")
        }
    }
}
#endif
