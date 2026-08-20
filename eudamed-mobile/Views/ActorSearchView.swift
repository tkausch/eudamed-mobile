import SwiftUI
import EudamedClient
import Observation

// MARK: - Actor Type

enum ActorType: String, CaseIterable, Identifiable {
    case manufacturer = "Manufacturer"
    case authorisedRepresentative = "Authorised Representative"
    case importer = "Importer"
    case systemProcedurePackProducer = "System/Procedure Pack Producer"

    var id: String { rawValue }

    var displayName: String {
        self == .systemProcedurePackProducer ? "System Pack Producer" : rawValue
    }

    var systemImage: String {
        switch self {
        case .manufacturer: return "gearshape"
        case .authorisedRepresentative: return "person.badge.checkmark"
        case .importer: return "shippingbox"
        case .systemProcedurePackProducer: return "square.stack.3d.up"
        }
    }
}

// MARK: - Actor Status

enum ActorStatus: String, CaseIterable, Identifiable {
    case active = "Active"
    case inactive = "Inactive"

    var id: String { rawValue }

    var color: Color {
        self == .active ? .green : .red
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ActorSearchViewModel {
    var name: String = ""
    var srn: String = ""
    var actorType: ActorType? = nil
    var statusFilter: ActorStatus? = nil
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

    var groupedActors: [(letter: String, actors: [Actor])] {
        let base: [Actor]
        if let statusFilter {
            base = actors.filter { actor in
                guard let status = actor.status else { return false }
                return status.localizedCaseInsensitiveCompare(statusFilter.rawValue) == .orderedSame
            }
        } else {
            base = actors
        }
        let sorted = base.sorted {
            ($0.name ?? $0.actorId).localizedCaseInsensitiveCompare($1.name ?? $1.actorId) == .orderedAscending
        }
        var result: [(letter: String, actors: [Actor])] = []
        for actor in sorted {
            let name = actor.name ?? actor.actorId
            let firstChar = String(name.prefix(1)).uppercased()
            let letter = firstChar.first?.isLetter == true ? firstChar : "#"
            if let last = result.last, last.letter == letter {
                result[result.count - 1].actors.append(actor)
            } else {
                result.append((letter: letter, actors: [actor]))
            }
        }
        return result
    }

    var sectionLetters: [String] {
        groupedActors.map(\.letter)
    }

    var canSearch: Bool {
        actorType != nil ||
        statusFilter != nil ||
        [name, srn, countryCode].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var displayedActorCount: Int {
        groupedActors.reduce(0) { $0 + $1.actors.count }
    }

    var activeFilterCount: Int {
        (actorType != nil ? 1 : 0) +
        (statusFilter != nil ? 1 : 0) +
        [name, srn, countryCode].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
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
            actorType: actorType?.rawValue,
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
        actorType = nil
        statusFilter = nil
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
    @State private var showingCountryPicker = false

    init(repository: any ActorRepository) {
        _viewModel = State(initialValue: ActorSearchViewModel(repository: repository))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                querySection

                if let msg = viewModel.validationMessage {
                    Section {
                        Label(msg, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if viewModel.hasSearched || viewModel.isLoading {
                    resultCountSection
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
            .overlay(alignment: .trailing) {
                if viewModel.sectionLetters.count >= 5 {
                    VStack {
                        Spacer()
                        SectionIndexView(letters: viewModel.sectionLetters) { letter in
                            proxy.scrollTo(letter, anchor: .top)
                        }
                        Spacer()
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .navigationTitle("Actors")
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
                Text("Search the EUDAMED database for registered economic operators. Results are fetched live from the European database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Actor name — the registered name of the operator", systemImage: "building.2")
                    Label("SRN — single registration number", systemImage: "number")
                    Label("Actor type — role in the supply chain (MF, AR, IM, PR)", systemImage: "person.badge.key")
                    Label("Country — country of registration", systemImage: "globe.europe.africa")
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
            TextField("Actor name", text: $viewModel.name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            TextField("SRN", text: $viewModel.srn)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))

            Picker("Actor type", selection: $viewModel.actorType) {
                Text("Any").tag(Optional<ActorType>.none)
                ForEach(ActorType.allCases) { type in
                    Text(type.displayName).tag(Optional(type))
                }
            }
            .tint(.blue)

            Picker("Status", selection: $viewModel.statusFilter) {
                Text("Any").tag(Optional<ActorStatus>.none)
                ForEach(ActorStatus.allCases) { status in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        Text(status.rawValue)
                    }
                    .tag(Optional(status))
                }
            }
            .tint(.blue)

            Button {
                showingCountryPicker = true
            } label: {
                HStack {
                    Text("Country")
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        if viewModel.countryCode.isEmpty {
                            Text("Any")
                        } else {
                            Text("\(viewModel.countryCode.countryFlag) \(Locale.current.localizedString(forRegionCode: viewModel.countryCode) ?? viewModel.countryCode)")
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .foregroundStyle(.blue)
                }
            }
            .sheet(isPresented: $showingCountryPicker) {
                CountryPickerView(selectedCode: $viewModel.countryCode)
            }
        }
    }

    // MARK: Result count

    private var resultCountSection: some View {
        let displayed = viewModel.displayedActorCount
        let total = viewModel.actors.count
        let text: String
        if viewModel.isLoading {
            text = "Searching…"
        } else if viewModel.statusFilter != nil && displayed != total {
            text = "\(displayed) of \(total) result\(total == 1 ? "" : "s")"
        } else {
            text = "\(displayed) result\(displayed == 1 ? "" : "s")"
        }
        return Section {
            HStack {
                Spacer()
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
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
            ForEach(viewModel.groupedActors, id: \.letter) { group in
                Section {
                    ForEach(Array(group.actors.enumerated()), id: \.element.id) { index, actor in
                        NavigationLink {
                            ActorDetailView(actor: actor)
                        } label: {
                            ActorRowView(actor: actor)
                        }
                        .id(index == 0 ? group.letter : actor.actorId)
                    }
                } header: {
                    Text(group.letter)
                }
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
                if let type = actor.actorType,
                   let actorType = ActorType(rawValue: type) {
                    Image(systemName: actorType.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let code = actor.countryIso2Code {
                    Text(code.countryFlag)
                        .font(.caption)
                }
                if let statusColor = statusIndicatorColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var statusIndicatorColor: Color? {
        guard let status = actor.status else { return nil }
        return ActorStatus.allCases.first {
            status.localizedCaseInsensitiveCompare($0.rawValue) == .orderedSame
        }?.color
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [actor.name ?? actor.actorId]
        if let type = actor.actorType { parts.append(type) }
        if let country = actor.countryName { parts.append(country) }
        parts.append("SRN \(actor.actorId)")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Section Index View

private struct SectionIndexView: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var selectedLetter: String? = nil
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private let itemHeight: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selectedLetter == letter ? Color.accentColor : .secondary)
                    .frame(width: 18, height: itemHeight)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !letters.isEmpty else { return }
                    let rawIndex = Int(value.location.y / itemHeight)
                    let index = max(0, min(letters.count - 1, rawIndex))
                    let letter = letters[index]
                    if letter != selectedLetter {
                        selectedLetter = letter
                        onSelect(letter)
                        feedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    selectedLetter = nil
                }
        )
    }
}

// MARK: - Country Picker

private extension String {
    var countryFlag: String {
        unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            let value = Int(scalar.value) - 65 + 127462
            guard value >= 0 else { return nil }
            return Unicode.Scalar(UInt32(value))
        }.map { String($0) }.joined()
    }
}

struct CountryPickerView: View {
    @Binding var selectedCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private static let countries: [(code: String, name: String)] = Locale.Region.isoRegions
        .compactMap { region in
            let code = region.identifier
            guard code.count == 2,
                  code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }),
                  let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
            return (code: code, name: name)
        }
        .sorted { $0.name < $1.name }

    private var filtered: [(code: String, name: String)] {
        guard !searchText.isEmpty else { return Self.countries }
        return Self.countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedCode = ""
                    dismiss()
                } label: {
                    HStack {
                        Text("Any country")
                        Spacer()
                        if selectedCode.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.secondary)

                ForEach(filtered, id: \.code) { country in
                    Button {
                        selectedCode = country.code
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(country.code.countryFlag) \(country.name)")
                            Spacer()
                            Text(country.code)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                            if selectedCode == country.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
