import SwiftUI
import EudamedClient

struct DeviceDetailView: View {
    let device: UdiDevice
    var onScanAgain: (() -> Void)? = nil

    var body: some View {
        List {
            versionWarning
            statusSection
            identificationSection
            classificationSection
            if hasCharacteristics { characteristicsSection }
            manufacturerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(device.tradeName ?? device.deviceName ?? device.primaryDi)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(onScanAgain != nil)
        .toolbar {
            if let onScanAgain {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onScanAgain) {
                        Label("Scan", systemImage: "barcode.viewfinder")
                    }
                    .tint(.blue)
                }
            }
        }
    }

    // MARK: Version warning (shown when not on latest)

    @ViewBuilder
    private var versionWarning: some View {
        if let version = device.versionNumber,
           let latest = device.latestVersion,
           version < latest {
            Section {
                Label(
                    "Viewing version \(version) — version \(latest) is available in EUDAMED.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Status (first full section — visible without scrolling)

    private var statusSection: some View {
        Section {
            if let status = device.status ?? device.statusId.map({ "ID \($0)" }) {
                LabeledContent("Record status", value: status)
            }
            if let deviceStatusType = device.deviceStatusType ?? device.deviceStatusTypeId.map({ "ID \($0)" }) {
                LabeledContent("Device status", value: deviceStatusType)
            }
            if let market = device.placedOnTheMarket ?? device.placedOnTheMarketId.map({ "ID \($0)" }) {
                LabeledContent("Placed on the market", value: market)
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: Identification

    private var identificationSection: some View {
        Section {
            LabeledContent("Primary DI") {
                HStack(spacing: 8) {
                    Text(device.primaryDi)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = device.primaryDi
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let basicUdi = device.basicUdi {
                LabeledContent("Basic UDI-DI", value: basicUdi)
                    .font(.system(.body, design: .monospaced))
            }
            if let tradeName = device.tradeName {
                LabeledContent("Trade name", value: tradeName)
            }
            if let deviceName = device.deviceName {
                LabeledContent("Device name", value: deviceName)
            }
            if let model = device.deviceModel {
                LabeledContent("Model", value: model)
            }
            if let ref = device.reference {
                LabeledContent("Reference", value: ref)
            }
            if let ddi = device.directMarketingDi {
                LabeledContent("Direct marketing DI", value: ddi)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("Identification")
        }
    }

    // MARK: Classification

    private var classificationSection: some View {
        Section {
            if let riskClass = device.riskClass ?? device.riskClassId.map({ "ID \($0)" }) {
                LabeledContent("Risk class", value: riskClass)
            }
            if let legislation = device.applicableLegislation ?? device.applicableLegislationId.map({ "ID \($0)" }) {
                LabeledContent("Applicable legislation", value: legislation)
            }
            if let code = device.nomenclatureCode {
                LabeledContent("Nomenclature code", value: code)
            }
            if let criterion = device.deviceCriterion {
                LabeledContent("Device criterion", value: criterion)
            }
        } header: {
            Text("Classification")
        }
    }

    // MARK: Characteristics

    private var hasCharacteristics: Bool {
        [device.implantable, device.sterile, device.sterilization,
         device.reusable, device.reprocessed, device.measuringFunction,
         device.administeringMedicine, device.humanTissues, device.animalTissues,
         device.humanProduct, device.medicinalProduct, device.cmrSubstance,
         device.endocrineDisruptor, device.latex, device.companionDiagnostics
        ].contains { $0 != nil }
    }

    private var characteristicsSection: some View {
        Section {
            characteristicRow("Implantable", value: device.implantable)
            characteristicRow("Sterile", value: device.sterile)
            characteristicRow("Requires sterilization", value: device.sterilization)
            characteristicRow("Reusable", value: device.reusable)
            characteristicRow("Reprocessed single-use", value: device.reprocessed)
            characteristicRow("Measuring function", value: device.measuringFunction)
            characteristicRow("Administering medicinal product", value: device.administeringMedicine)
            characteristicRow("Human tissues", value: device.humanTissues)
            characteristicRow("Animal tissues", value: device.animalTissues)
            characteristicRow("Human blood/plasma product", value: device.humanProduct)
            characteristicRow("Medicinal product", value: device.medicinalProduct)
            characteristicRow("CMR substance", value: device.cmrSubstance)
            characteristicRow("Endocrine disruptor", value: device.endocrineDisruptor)
            characteristicRow("Latex", value: device.latex)
            characteristicRow("Companion diagnostics", value: device.companionDiagnostics)
        } header: {
            Text("Characteristics")
        }
    }

    @ViewBuilder
    private func characteristicRow(_ label: String, value: Int?) -> some View {
        if let v = value {
            LabeledContent(label, value: v == 1 ? "Yes" : "No")
        }
    }

    // MARK: Manufacturer

    private var manufacturerSection: some View {
        Section {
            if let name = device.mfName {
                LabeledContent("Name", value: name)
            }
            if let srn = device.mfSrn {
                LabeledContent("SRN", value: srn)
                    .font(.system(.body, design: .monospaced))
            }
            if let names = device.mfActorNames {
                LabeledContent("Actor names", value: names)
            }
            if let abbr = device.actorAbbreviatedNames {
                LabeledContent("Abbreviated names", value: abbr)
            }
        } header: {
            Text("Manufacturer")
        }
    }
}
