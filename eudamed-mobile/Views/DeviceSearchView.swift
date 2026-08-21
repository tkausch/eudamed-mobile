import SwiftUI
import EudamedClient
import Observation

// MARK: - ViewModel

@MainActor
@Observable
final class DeviceSearchViewModel {
    var tradeName: String = ""
    var mfSrn: String = ""
    var primaryDi: String = ""
    var basicUdi: String = ""

    private(set) var isLoading = false
    private(set) var devices: [UdiDevice] = []
    private(set) var hasSearched = false
    private(set) var searchError: Error? = nil
    private(set) var validationMessage: String? = nil

    private let repository: any UdiDevicesRepository
    private var searchTask: Task<Void, Never>?

    init(repository: any UdiDevicesRepository) {
        self.repository = repository
    }

    var canSearch: Bool {
        [tradeName, mfSrn, primaryDi, basicUdi].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var isSrnValid: Bool { SRNValidator.isValid(mfSrn) }
    var isPrimaryDiValid: Bool { DeviceIdentifierValidator.isValid(primaryDi) }
    var isBasicUdiValid: Bool { DeviceIdentifierValidator.isValid(basicUdi) }

    var activeFilterCount: Int {
        [tradeName, mfSrn, primaryDi, basicUdi].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    func search() {
        guard canSearch else {
            validationMessage = "Enter at least one search criterion."
            return
        }
        guard isSrnValid else {
            validationMessage = "Invalid SRN - has wrong format"
            return
        }
        guard isPrimaryDiValid else {
            validationMessage = "Invalid Primary DIFor the "
            return
        }
        guard isBasicUdiValid else {
            validationMessage = "Invalid Basic UDI-DI"
            return
        }
        validationMessage = nil
        searchTask?.cancel()

        let query = UdiDevicesQuery(
            primaryDi: primaryDi.trimmedOrNil,
            basicUdi: basicUdi.trimmedOrNil,
            tradeName: tradeName.trimmedOrNil,
            mfSrn: mfSrn.trimmedOrNil
        )

        isLoading = true
        searchError = nil

        searchTask = Task {
            do {
                let results = try await repository.search(query: query)
                guard !Task.isCancelled else { return }
                devices = results
                hasSearched = true
                isLoading = false
            } catch is CancellationError {
                isLoading = false
            } catch {
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }
                searchError = error
                hasSearched = true
                isLoading = false
            }
        }
    }

    func cancel() {
        searchTask?.cancel()
        isLoading = false
    }

    func clear() {
        searchTask?.cancel()
        tradeName = ""
        mfSrn = ""
        primaryDi = ""
        basicUdi = ""
        devices = []
        hasSearched = false
        searchError = nil
        validationMessage = nil
        isLoading = false
    }
}

private extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

// MARK: - View

struct DeviceSearchView: View {
    @State private var viewModel: DeviceSearchViewModel

    init(repository: any UdiDevicesRepository) {
        _viewModel = State(initialValue: DeviceSearchViewModel(repository: repository))
    }

    var body: some View {
        List {
            querySection

            if let msg = viewModel.validationMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            if viewModel.isLoading {
                loadingSection
            } else if let error = viewModel.searchError {
                errorSection(error)
            } else if viewModel.hasSearched {
                resultsSection
            } else {
                introSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Devices")
        .toolbar {
            toolbarContent
        }
        .onSubmit {
            viewModel.search()
        }
    }

    // MARK: Intro (shown before first search)

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search the EUDAMED database for registered medical devices. Results are fetched live from the European database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Trade name — the name on the device label", systemImage: "tag")
                    Label("Manufacturer SRN — the operator's registration number", systemImage: "building.2")
                    Label("Primary DI — unique device identifier", systemImage: "barcode")
                    Label("Basic UDI-DI — device family identifier", systemImage: "square.stack")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Query form

    private var querySection: some View {
        Section("Search criteria") {
            TextField("Trade name", text: $viewModel.tradeName)
                .autocorrectionDisabled()

            TextField("Manufacturer SRN", text: $viewModel.mfSrn)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))

            TextField("Primary DI", text: $viewModel.primaryDi)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))

            TextField("Basic UDI-DI", text: $viewModel.basicUdi)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: Loading

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView("Searching EUDAMED…")
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Error

    private func errorSection(_ error: Error) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Search failed", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.search()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.devices.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No results", systemImage: "magnifyingglass")
                        .font(.headline)
                    Text("EUDAMED returned no devices for your search criteria. Try broadening the filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.clear()
                    } label: {
                        Label("Clear filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            Section {
                ForEach(viewModel.devices) { device in
                    NavigationLink {
                        DeviceDetailView(device: device)
                    } label: {
                        DeviceRowView(device: device)
                    }
                }
            } header: {
                Text("\(viewModel.devices.count) result\(viewModel.devices.count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.isLoading {
                Button {
                    viewModel.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                .tint(.blue)
            } else {
                if viewModel.hasSearched || viewModel.activeFilterCount > 0 {
                    Button {
                        viewModel.clear()
                    } label: {
                        Label("Reset", systemImage: "arrow.clockwise")
                    }
                    .tint(.blue)
                }

                Button {
                    viewModel.search()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(!viewModel.canSearch)
                .tint(.blue)
            }
        }
    }
}

// MARK: - Device Row

struct DeviceRowView: View {
    let device: UdiDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(device.deviceName ?? device.tradeName ?? device.primaryDi)
                .font(.body)
                .fontWeight(.medium)

            Text("UDI: \(device.primaryDi)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)

            metaLine
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    @ViewBuilder
    private var metaLine: some View {
        let parts = [device.deviceStatusType, device.placedOnTheMarket]
            .compactMap { $0 }
        if !parts.isEmpty {
            HStack(spacing: 4) {
                if let statusType = device.deviceStatusType {
                    Circle()
                        .fill(statusType.localizedCaseInsensitiveContains("no longer") ? Color.red : Color.green)
                        .frame(width: 7, height: 7)
                }
                Text(parts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [device.deviceName ?? device.tradeName ?? device.primaryDi]
        parts.append("Primary DI \(device.primaryDi)")
        if let statusType = device.deviceStatusType { parts.append(statusType) }
        if let market = device.placedOnTheMarket { parts.append(market) }
        return parts.joined(separator: ", ")
    }
}
