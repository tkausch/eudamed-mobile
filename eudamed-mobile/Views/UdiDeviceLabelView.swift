import SwiftUI
import EudamedClient

struct UdiDeviceLabelView: View {
    let device: UdiDevice
    /// When true, a (01) badge appears next to the UDI-DI row to guide manual entry.
    var highlightPrimaryDI: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            diSection
            Divider()
            footerSection
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.label), lineWidth: 1.5)
        )
    }

    // MARK: Header – device name and risk class badge

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.tradeName ?? device.deviceName ?? device.primaryDi)
                    .font(.headline)
                    .fontWeight(.bold)
                if let deviceName = device.deviceName, device.tradeName != nil {
                    Text(deviceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let model = device.deviceModel {
                    Text("Model: \(model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let riskClassId = device.riskClassId {
                Text("Class \(riskClassLabel(riskClassId))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskClassColor(riskClassId).opacity(0.15))
                    .foregroundStyle(riskClassColor(riskClassId))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
    }

    // MARK: DI codes

    private var diSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            diRow(label: "UDI-DI", value: device.primaryDi, systemImage: "barcode", badge: highlightPrimaryDI ? "(01)" : nil)
            if let basicUdi = device.basicUdi {
                diRow(label: "Basic UDI-DI", value: basicUdi, systemImage: "square.stack")
            }
            if let ref = device.reference {
                diRow(label: "REF", value: ref, systemImage: "tag")
            }
        }
        .padding()
    }

    private func diRow(label: String, value: String, systemImage: String, badge: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: Footer – manufacturer and characteristic icons

    private var footerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let mfName = device.mfName {
                    Label(mfName, systemImage: "building.2")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if let srn = device.mfSrn {
                    Text("SRN: \(srn)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }
            }
            Spacer()
            characteristicIcons
        }
        .padding()
    }

    private var characteristicIcons: some View {
        HStack(spacing: 10) {
            if device.sterile == 1 {
                characteristicIcon(symbol: "snowflake", label: "STERILE")
            }
            if device.implantable == 1 {
                characteristicIcon(symbol: "arrow.down.to.line", label: "IMPL.")
            }
            if device.reusable == 1 {
                characteristicIcon(symbol: "arrow.2.circlepath", label: "REUSE")
            }
            if device.latex == 1 {
                characteristicIcon(symbol: "allergens", label: "LATEX")
            }
        }
    }

    private func characteristicIcon(symbol: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 7))
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Helpers

    private func riskClassLabel(_ id: Int) -> String {
        switch id {
        case 1: return "I"
        case 2: return "IIa"
        case 3: return "IIb"
        case 4: return "III"
        default: return "\(id)"
        }
    }

    private func riskClassColor(_ id: Int) -> Color {
        switch id {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        default: return .secondary
        }
    }
}

// MARK: - Sample data helper

extension UdiDevice {
    static var sampleForDemo: UdiDevice {
        let d = UdiDevice(primaryDi: "04007221088620")
        d.tradeName = "GlucaSense Pro"
        d.deviceName = "Continuous Glucose Monitoring System"
        d.deviceModel = "GSP-3000"
        d.mfName = "MedTech Solutions GmbH"
        d.mfSrn = "DE-MF-000012345"
        d.basicUdi = "AT380740001968"
        d.reference = "GSP3K-EU-001"
        d.riskClassId = 3
        d.sterile = 1
        return d
    }
}

// MARK: - Preview

#Preview("Label") {
    UdiDeviceLabelView(device: .sampleForDemo)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Label – manual entry annotation") {
    UdiDeviceLabelView(device: .sampleForDemo, highlightPrimaryDI: true)
        .padding()
        .background(Color(.systemGroupedBackground))
}
