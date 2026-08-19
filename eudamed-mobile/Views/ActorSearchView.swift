import SwiftUI
import EudamedClient
import Observation

// MARK: - ViewModel

@MainActor
@Observable
final class ActorSearchViewModel {
    var name: String = ""
    var srn: String = ""
    var actorType: String = ""
    var countryCode: String = ""

    private(set) var isLoading = false
    private(set) var actors: [Actor] = []
    private(set) var hasSearched = false
    private(set) var searchError: Error? = nil
    private(set) var validationMessage: String? = nil

    private let repository: any ActorRepository
    private var searchTask: Task<Void, Never>?

    init(repository: any ActorRepository) {
        self.repository = repository
    }

    var canSearch: Bool {
        [name, srn, actorType, countryCode].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var activeFilterCount: Int {
        [name, srn, actorType, countryCode].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    func search() {
        guard canSearch else {
            validationMessage = "Enter at least one search criterion."
            return
        }
        validationMessage = nil
        searchTask?.cancel()

        let query = ActorQuery(
            actorId: srn.trimmedOrNil,
            name: name.trimmedOrNil,
            actorType: actorType.trimmedOrNil,
            countryIso2Code: countryCode.trimmedOrNil
        )

        isLoading = true
        searchError = nil

        searchTask = Task {
            do {
                let results = try await repository.search(query: query)
                guard !Task.isCancelled else { return }
                actors = results
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
        name = ""
        srn = ""
        actorType = ""
        countryCode = ""
        actors = []
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

struct ActorSearchView: View {
    @State private var viewModel: ActorSearchViewModel

    init(repository: any ActorRepository) {
        _viewModel = State(initialValue: ActorSearchViewModel(repository: repository))
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
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Actors")
        .toolbar {
            toolbarContent
        }
        .onSubmit {
            viewModel.search()
        }
    }

    // MARK: Query form

    private var querySection: some View {
        Section("Search criteria") {
            TextField("Actor name", text: $viewModel.name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            TextField("SRN", text: $viewModel.srn)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))

            TextField("Actor type (e.g. MF, AR, IM)", text: $viewModel.actorType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)

            TextField("Country code (e.g. DE, FR)", text: $viewModel.countryCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)

            Button {
                viewModel.search()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .disabled(!viewModel.canSearch || viewModel.isLoading)
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
        if viewModel.actors.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No results", systemImage: "magnifyingglass")
                        .font(.headline)
                    Text("EUDAMED returned no actors for your search criteria. Try broadening the filters.")
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
                ForEach(viewModel.actors) { actor in
                    NavigationLink {
                        ActorDetailView(actor: actor)
                    } label: {
                        ActorRowView(actor: actor)
                    }
                }
            } header: {
                Text("\(viewModel.actors.count) result\(viewModel.actors.count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isLoading {
                Button {
                    viewModel.cancel()
                } label: {
                    Label("Cancel search", systemImage: "xmark.circle.fill")
                }
            } else if viewModel.hasSearched || viewModel.activeFilterCount > 0 {
                Button {
                    viewModel.clear()
                } label: {
                    Label("Clear", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

// MARK: - Actor Row

struct ActorRowView: View {
    let actor: Actor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(actor.name ?? actor.actorId)
                .font(.body)
                .fontWeight(.medium)

            Text(actor.actorId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)

            HStack(spacing: 8) {
                if let type = actor.actorType {
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let country = actor.countryName ?? actor.countryIso2Code {
                    Text(country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [actor.name ?? actor.actorId]
        if let type = actor.actorType { parts.append(type) }
        if let country = actor.countryName { parts.append(country) }
        parts.append("SRN \(actor.actorId)")
        return parts.joined(separator: ", ")
    }
}
