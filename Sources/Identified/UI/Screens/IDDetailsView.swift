#if os(iOS)
import IdentifiedCore
import SwiftUI

/// `IdDetails.tsx`. iOS keeps the native date picker, as the web does on iOS.
struct IDDetailsView: View {
    @EnvironmentObject private var flow: FlowModel
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @State private var dob: Date?
    @State private var idType: String?
    @State private var idNumber = ""
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    @State private var showsDatePicker = false
    @State private var selectedDate = Date()

    var body: some View {
        let options = IDDetailsInput.options(allowed: flow.session?.allowedIdTypes ?? [])
        let isGhanaCard = idType == IDDetailsInput.nationalID
        FlowScaffold(title: L10n.string("id.title"), subtitle: L10n.string("id.subtitle"), step: .idDetails) {
            VStack(alignment: .leading, spacing: 16) {
                FieldBox(label: L10n.string("id.dob")) {
                    Button {
                        selectedDate = dob ?? defaultDate
                        showsDatePicker = true
                    } label: {
                        closedTrigger(value: dob.map { $0.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)) }, symbol: "calendar")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("id.dob"))
                    .accessibilityValue(dob.map { $0.formatted(date: .long, time: .omitted) } ?? "")
                }
                FieldBox(label: L10n.string("id.type"), isFilled: idType != nil) {
                    Menu {
                        ForEach(options, id: \.key) { option in
                            Button { idType = option.key } label: {
                                if idType == option.key {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        closedTrigger(value: options.first(where: { $0.key == idType })?.label, symbol: "chevron.down")
                    }
                    .accessibilityLabel(L10n.string("id.type"))
                    .accessibilityValue(options.first(where: { $0.key == idType })?.label ?? L10n.string("id.type_placeholder"))
                    .disabled(options.count == 1)
                }
                FieldBox(label: isGhanaCard ? L10n.string("id.number_ghana") : L10n.string("id.number"), isFilled: !idNumber.isEmpty) {
                    TextField("", text: $idNumber)
                        .textInputAutocapitalization(isGhanaCard ? .characters : .never)
                        .autocorrectionDisabled()
                }
                if isGhanaCard {
                    BodyText(L10n.string("id.ghana_helper"), secondary: true, size: 13)
                }
                if let error { ErrorText(message: error) }
            }
        } footer: {
            PrimaryButton(
                title: L10n.string("flow.continue"), busyTitle: L10n.string("flow.saving"), busy: busy,
                enabled: !idNumber.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                Task { await save() }
            }
        }
        .onAppear { prefill(options) }
        .sheet(isPresented: $showsDatePicker) { datePickerSheet }
    }

    private func closedTrigger(value: String?, symbol: String) -> some View {
        HStack(spacing: 12) {
            Text(value ?? " ").font(theme.body(18)).foregroundStyle(theme.palette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.palette.textSecondary).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        // Expand the hit surface to include the FieldBox's interior padding.
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 8)
        .contentShape(Rectangle())
        .padding(.horizontal, -16).padding(.top, -24).padding(.bottom, -8)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            ScrollView {
                DatePicker(L10n.string("id.dob"), selection: $selectedDate,
                           in: earliest...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(20)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle(L10n.string("id.dob"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("flow.done")) {
                        dob = selectedDate
                        showsDatePicker = false
                    }
                    .foregroundStyle(theme.palette.accent)
                }
            }
        }
        .environment(\.theme, theme)
        .tint(theme.palette.accent)
    }

    /// The web opens its picker 25 years back and allows 120.
    private var defaultDate: Date { Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date() }
    private var earliest: Date { Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast }

    private func prefill(_ options: [IDTypeOption]) {
        guard !loaded else { return }
        loaded = true
        let details = flow.session?.idDetails
        dob = details?.dob.flatMap(IDDetailsInput.date(fromDOB:))
        idType = details?.idType.flatMap { saved in options.contains { $0.key == saved } ? saved : nil }
        if options.count == 1 { idType = options[0].key }
        idNumber = details?.idNumber ?? ""
    }

    private func save() async {
        error = nil
        switch IDDetailsInput.validate(dob: dob, idType: idType, idNumber: idNumber) {
        case .missingDateOfBirth:
            error = L10n.string("id.missing_dob")
            return
        case .missingType:
            error = L10n.string("id.missing_type")
            return
        case .invalidGhanaCard:
            error = L10n.string("id.invalid_ghana")
            return
        case nil:
            break
        }
        guard let dob, let idType else { return }
        busy = true
        defer { busy = false }
        do {
            try await flow.saveIDDetails(dob: IDDetailsInput.dobString(dob), idType: idType, idNumber: idNumber.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            self.error = flow.message(for: error) ?? L10n.string("id.error")
        }
    }
}
#endif
