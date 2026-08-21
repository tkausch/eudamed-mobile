import SwiftUI
import VisionKit
import EudamedClient
import Observation

// MARK: - State

enum ScannerState {
    case intro
    case scanning
    case lookingUp(String)
    case notFound(String)
    case error(String, Error)
    case cameraRestricted

    var showsCamera: Bool {
        switch self {
        case .scanning, .lookingUp, .notFound: return true
        default: return false
        }
    }

    var cameraIsActive: Bool {
        if case .scanning = self { return true }
        return false
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ScannerViewModel {
    var state: ScannerState = .intro
    var manualInput: String = ""
    var navigateToDevice: UdiDevice? = nil
    var showUnsupportedAlert = false

    private let repository: any UdiDevicesRepository
    private var lookupTask: Task<Void, Never>?

    init(repository: any UdiDevicesRepository) {
        self.repository = repository
    }

    func startScanning() {
        guard DataScannerViewController.isSupported else {
            showUnsupportedAlert = true
            return
        }
        state = .scanning
    }

    func codeScanned(_ value: String) {
        guard case .scanning = state else { return }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        lookup(trimmed)
    }

    func lookup(_ identifier: String) {
        lookupTask?.cancel()
        state = .lookingUp(identifier)
        lookupTask = Task {
            do {
                let device = try await repository.device(primaryDi: identifier)
                guard !Task.isCancelled else { return }
                if let device {
                    navigateToDevice = device
                } else {
                    state = .notFound(identifier)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(identifier, error)
            }
        }
    }

    func submitManual() {
        let t = manualInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        lookup(t)
    }

    func rescan() {
        lookupTask?.cancel()
        state = .scanning
    }

    func resetAfterNavigation() {
        state = .intro
    }

    func cameraBecameRestricted() {
        state = .cameraRestricted
    }
}

// MARK: - DataScannerRepresentable

struct DataScannerRepresentable: UIViewControllerRepresentable {
    var isActive: Bool
    var onCodeScanned: (String) -> Void
    var onCameraRestricted: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onCameraRestricted: onCameraRestricted)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [
                    .qr, .code128, .ean13, .ean8, .code39,
                    .pdf417, .aztec, .dataMatrix
                ])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCodeScanned = onCodeScanned
        context.coordinator.onCameraRestricted = onCameraRestricted
        if isActive && !scanner.isScanning {
            context.coordinator.resetScanned()
            try? scanner.startScanning()
        }
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCodeScanned: (String) -> Void
        var onCameraRestricted: () -> Void
        private var scanned = false

        init(onCodeScanned: @escaping (String) -> Void, onCameraRestricted: @escaping () -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onCameraRestricted = onCameraRestricted
        }

        func resetScanned() { scanned = false }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !scanned else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    scanned = true
                    dataScanner.stopScanning()
                    onCodeScanned(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            if case .cameraRestricted = error {
                onCameraRestricted()
            }
        }
    }
}

// MARK: - ScannerView

struct ScannerView: View {
    @State private var viewModel: ScannerViewModel

    init(repository: any UdiDevicesRepository) {
        _viewModel = State(initialValue: ScannerViewModel(repository: repository))
    }

    var body: some View {
        @Bindable var vm = viewModel

        ZStack {
            // Camera view is stable across .scanning and .lookingUp to avoid
            // recreating the DataScannerViewController on state transitions.
            if viewModel.state.showsCamera {
                DataScannerRepresentable(
                    isActive: viewModel.state.cameraIsActive,
                    onCodeScanned: { viewModel.codeScanned($0) },
                    onCameraRestricted: { viewModel.cameraBecameRestricted() }
                )
            }

            switch viewModel.state {
            case .intro:
                introView
            case .scanning:
                EmptyView()
            case .lookingUp(let id):
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Searching EUDAMED…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            case .notFound:
                EmptyView()
            case .error(let id, let error):
                errorView(id, error)
            case .cameraRestricted:
                cameraRestrictedView
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $vm.navigateToDevice) { device in
            DeviceDetailView(device: device, onScanAgain: {
                vm.navigateToDevice = nil
            })
        }
        .onChange(of: vm.navigateToDevice) { old, new in
            if old != nil && new == nil {
                viewModel.resetAfterNavigation()
            }
        }
        .alert("Device Not Found", isPresented: Binding(
            get: { if case .notFound = viewModel.state { return true }; return false },
            set: { if !$0 { viewModel.rescan() } }
        )) {
            Button("Scan Again") { viewModel.rescan() }
        } message: {
            if case .notFound(let id) = viewModel.state {
                Text("EUDAMED has no entry for \"\(id)\".")
            }
        }
        .alert("Scanner Not Available", isPresented: $vm.showUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Live scanning requires a device with Neural Engine (iPhone XS or later).")
        }
    }

    // MARK: Intro

    private var introView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Point the camera at a barcode printed on a medical device label. The app reads the UDI and looks up the device in EUDAMED.")
                    .foregroundStyle(.secondary)

                Button(action: viewModel.startScanning) {
                    Label("Scan", systemImage: "barcode.viewfinder")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Example label")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image("SampleLabel")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                #if targetEnvironment(simulator)
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter UDI manually")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        TextField("00889024505414", text: $viewModel.manualInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { viewModel.submitManual() }

                        Button {
                            viewModel.submitManual()
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                        }
                        .disabled(viewModel.manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                #endif
            }
            .padding()
        }
    }

    // MARK: Error

    private func errorView(_ identifier: String, _ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Lookup failed")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    viewModel.lookup(identifier)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.rescan()
                } label: {
                    Label("Scan Again", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Camera restricted

    private var cameraRestrictedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Camera access required")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Allow camera access in Settings to scan device barcodes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
