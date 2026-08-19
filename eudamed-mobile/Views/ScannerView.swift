import SwiftUI
import VisionKit
import EudamedClient
import Observation

// MARK: - State

enum ScannerState {
    case intro
    case scanning
    case lookingUp(String)
    case error(String, Error)
    case cameraRestricted
    case unsupported
}

// MARK: - ViewModel

@MainActor
@Observable
final class ScannerViewModel {
    var state: ScannerState
    var manualInput: String = ""
    var navigateToDevice: UdiDevice? = nil

    private let repository: any UdiDevicesRepository
    private var lookupTask: Task<Void, Never>?

    init(repository: any UdiDevicesRepository) {
        self.repository = repository
        self.state = DataScannerViewController.isSupported ? .intro : .unsupported
    }

    func startScanning() {
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
                    state = .intro
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
        state = .scanning
    }

    func cameraBecameRestricted() {
        state = .cameraRestricted
    }
}

// MARK: - DataScannerRepresentable

struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    var onCameraRestricted: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onCameraRestricted: onCameraRestricted)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.qr, .code128, .ean13, .ean8, .code39, .pdf417, .aztec])
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
        if !scanner.isScanning {
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

        Group {
            switch viewModel.state {
            case .intro:
                introView
            case .scanning:
                scanningView
            case .lookingUp(let id):
                lookingUpView(id)
            case .error(let id, let error):
                errorView(id, error)
            case .cameraRestricted:
                cameraRestrictedView
            case .unsupported:
                unsupportedView
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $vm.navigateToDevice) { device in
            DeviceDetailView(device: device)
        }
        .onChange(of: vm.navigateToDevice) { old, new in
            if old != nil && new == nil {
                viewModel.resetAfterNavigation()
            }
        }
    }

    // MARK: Intro

    private var introView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Point the camera at a barcode printed on a medical device label. The app reads the UDI and looks up the device in EUDAMED.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Example label")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image("SampleLabel")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter UDI manually")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        TextField("Primary DI (01)", text: $viewModel.manualInput)
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

                Text("Supported formats: QR · Code 128 · EAN-13 · EAN-8 · Code 39 · PDF-417 · Aztec")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    viewModel.startScanning()
                } label: {
                    Label("Start Scanning", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    // MARK: Scanning

    private var scanningView: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(
                onCodeScanned: { viewModel.codeScanned($0) },
                onCameraRestricted: { viewModel.cameraBecameRestricted() }
            )

            VStack(spacing: 12) {
                Text("Or enter an identifier manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Primary DI", text: $viewModel.manualInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .onSubmit { viewModel.submitManual() }

                    Button {
                        viewModel.submitManual()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                    }
                    .disabled(viewModel.manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    // MARK: Looking up

    private func lookingUpView(_ identifier: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 4) {
                Text("Looking up in EUDAMED…")
                    .font(.headline)
                Text(identifier)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                viewModel.rescan()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: Unsupported

    private var unsupportedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scanner not available")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Live scanning requires a device with Neural Engine (iPhone XS or later). Enter the UDI manually instead.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Example label")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image("SampleLabel")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter UDI manually")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        TextField("Primary DI (01)", text: $viewModel.manualInput)
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
            }
            .padding()
        }
    }
}
