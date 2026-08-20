import SwiftUI
import EudamedClient

struct ActorDetailView: View {
    let actor: Actor

    @State private var srnCopied = false

    var body: some View {
        List {
            registrationSection
            identitySection
            if hasContactInfo { contactSection }
            if hasAddressInfo { addressSection }
            if hasPrrc { prrcSection }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Actor Details")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Registration (shown first — status visible in first screenful)

    private var registrationSection: some View {
        Section("Registration") {
            if let status = actor.status {
                LabeledContent("Status") {
                    if isActiveStatus(status) {
                        Text(status)
                    } else {
                        Text(status)
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                    }
                }
            }

            // SRN with copy action
            HStack {
                LabeledContent("SRN", value: actor.actorId)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button {
                    UIPasteboard.general.string = actor.actorId
                    srnCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        srnCopied = false
                    }
                } label: {
                    Image(systemName: srnCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel(srnCopied ? "SRN copied" : "Copy SRN")
                .buttonStyle(.plain)
            }

            if let date = actor.statusFromDate {
                LabeledContent("Status since", value: date)
            }

            if let version = actor.version {
                LabeledContent("Version", value: "\(version)")
            }
        }
    }

    // MARK: Identity

    private var identitySection: some View {
        Section("Identity") {
            if let name = actor.name {
                LabeledContent("Legal name", value: name)
            }

            if let abbr = actor.abbreviatedName {
                LabeledContent("Abbreviated name", value: abbr)
            }

            if let type = actor.actorType {
                LabeledContent("Actor type", value: type)
            }

            if let country = actor.countryName {
                LabeledContent("Country", value: country)
            } else if let code = actor.countryIso2Code {
                LabeledContent("Country", value: code)
            }

            if let vat = actor.europeanVatNumber {
                LabeledContent("EU VAT number", value: vat)
            }
        }
    }

    // MARK: Contact

    private var hasContactInfo: Bool {
        actor.email != nil || actor.telephone != nil || actor.website != nil
    }

    private var contactSection: some View {
        Section("Contact") {
            if let email = actor.email {
                LabeledContent("Email", value: email)
            }
            if let phone = actor.telephone {
                LabeledContent("Telephone", value: phone)
            }
            if let web = actor.website {
                LabeledContent("Website", value: web)
            }
        }
    }

    // MARK: Address

    private var hasAddressInfo: Bool {
        actor.addressStreetName != nil || actor.addressCityName != nil ||
        actor.addressPostalZone != nil || actor.addressCountryName != nil
    }

    private var addressSection: some View {
        Section("Address") {
            if let building = actor.addressBuildingNumber, let street = actor.addressStreetName {
                LabeledContent("Street", value: "\(building) \(street)")
            } else if let street = actor.addressStreetName {
                LabeledContent("Street", value: street)
            }

            if let postBox = actor.addressPostBox {
                LabeledContent("Post box", value: postBox)
            }

            if let zone = actor.addressPostalZone, let city = actor.addressCityName {
                LabeledContent("City", value: "\(zone) \(city)")
            } else if let city = actor.addressCityName {
                LabeledContent("City", value: city)
            }

            if let country = actor.addressCountryName {
                LabeledContent("Country", value: country)
            } else if let code = actor.addressCountryCode {
                LabeledContent("Country", value: code)
            }
        }
    }

    // MARK: PRRC

    private var hasPrrc: Bool {
        actor.prrcFirstName != nil || actor.prrcFamilyName != nil
    }

    private var prrcSection: some View {
        Section("Person Responsible for Regulatory Compliance") {
            let fullName = [actor.prrcFirstName, actor.prrcFamilyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !fullName.isEmpty {
                LabeledContent("Name", value: fullName)
            }
        }
    }

    // MARK: Helpers

    private func isActiveStatus(_ status: String) -> Bool {
        let upper = status.uppercased()
        return upper.contains("ACTIVE") || upper.contains("VALID") || upper.contains("REGISTERED")
    }
}
