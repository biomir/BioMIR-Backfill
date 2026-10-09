import SwiftUI
import UniformTypeIdentifiers

struct ImportFlowView: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var showImporter = false
    @State private var showImportConfirmation = false
    @State private var showNoonRepairConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    stageProgress
                    stageCard
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                    safetyFooter
                }
                .padding()
            }
            .navigationTitle("BioMIR Backfill")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await viewModel.selectSource(url: url) }
                    }
                case .failure:
                    break
                }
            }
            .confirmationDialog(
                "Import eligible historical nutrition data?",
                isPresented: $showImportConfirmation,
                titleVisibility: .visible
            ) {
                Button("Import to Apple Health") {
                    Task { await viewModel.performImport() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("BioMIR Backfill will rerun preflight immediately before writing. If anything changed, the import will stop for another review.")
            }
            .confirmationDialog(
                "Remove legacy full-day BioMIR Backfill nutrition samples?",
                isPresented: $showNoonRepairConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Legacy Backfill Samples", role: .destructive) {
                    Task { await viewModel.performHistoricalNutritionNoonRepairDeletion() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One-time timestamp recovery only. This targets BioMIR Backfill-authored historical nutrition samples from 2021-03-11 through 2025-01-08 using mapping versions nutrition-v0.1 or carbmanager-total-carb-v1, and only the legacy positive-duration representation. New noon-point samples are excluded.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 40, weight: .semibold))
                .accessibilityHidden(true)
            Text("Bring your history to Apple Health")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Review mappings, collision screening, provenance, and verification before accepting the result.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stageProgress: some View {
        HStack(spacing: 8) {
            ForEach(ImportStage.allCases) { item in
                VStack(spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.body.weight(item == viewModel.stage ? .semibold : .regular))
                    Text(item.title)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(item == viewModel.stage ? .primary : .secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import progress")
    }

    @ViewBuilder
    private var stageCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(viewModel.stage.title, systemImage: viewModel.stage.systemImage)
                        .font(.headline)
                    Spacer()
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                switch viewModel.stage {
                case .selectSource:
                    selectSourceContent
                case .review:
                    reviewContent
                case .preflight:
                    preflightContent
                case .results:
                    resultsContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var selectSourceContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a compatible historical nutrition CSV. The file stays local to this device.")
                .foregroundStyle(.secondary)
            Button {
                showImporter = true
            } label: {
                Label("Choose CSV", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("One-time timestamp recovery")
                    .font(.subheadline.weight(.semibold))
                Text("Use only to remove the legacy midnight-to-midnight BioMIR Backfill historical nutrition imports before re-importing them as 12:00 PM point samples.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showNoonRepairConfirmation = true
                } label: {
                    Label("Remove Legacy Full-Day Imports", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRunHistoricalNutritionNoonRepair)

                if let repair = viewModel.repairSummary {
                    Label(
                        "Removed \(repair.deletedCount) legacy samples",
                        systemImage: repair.matchesExpectedCount ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    Text(
                        repair.matchesExpectedCount
                        ? "Expected count confirmed: \(repair.expectedCount). Proceed to controlled noon-anchor re-import."
                        : "Expected \(repair.expectedCount). Do not re-import yet; preserve this result for investigation."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let summary = viewModel.reviewSummary {
            VStack(alignment: .leading, spacing: 14) {
                summaryRows([
                    ("File", summary.filename),
                    ("SHA-256", summary.fingerprintPrefix + "…"),
                    ("Rows", "\(summary.rowCount)"),
                    ("Date range", dateRange(summary.dateStart, summary.dateEnd)),
                    ("Supported mappings", "\(summary.supportedMappingCount)"),
                    ("Unsupported fields", "\(summary.unsupportedMappingCount)"),
                    ("Mapping", summary.mappingVersion)
                ])

                if !summary.unsupportedFields.isEmpty {
                    Divider()
                    Text("Unsupported fields")
                        .font(.subheadline.weight(.semibold))
                    ForEach(summary.unsupportedFields, id: \.sourceColumn) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.sourceColumn)
                            Text(field.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Choose Another") { viewModel.reset(); showImporter = true }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Continue to Preflight") { viewModel.continueToPreflight() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Text("No reviewed source is available.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var preflightContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Authorize only the controlled nutrition types and inspect visible collisions before any write occurs.")
                .foregroundStyle(.secondary)

            if let summary = viewModel.preflightSummary {
                summaryRows([
                    ("Eligible", "\(summary.eligibleCount)"),
                    ("Existing visible", "\(summary.existingCount)"),
                    ("Missing", "\(summary.missingCount)"),
                    ("Zero-policy skips", "\(summary.zeroPolicyCount)"),
                    ("Authorization blocked", "\(summary.authorizationBlockedCount)"),
                    ("Unsupported fields", "\(summary.unsupportedFieldCount)")
                ])

                if let warning = summary.visibilityWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("preflightVisibilityWarning")
                }

                Toggle(
                    "I reviewed these preflight results",
                    isOn: Binding(
                        get: { viewModel.preflightReviewed },
                        set: { viewModel.setPreflightReviewed($0) }
                    )
                )

                Button("Import Eligible Data") {
                    showImportConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canImport)
            } else {
                Button("Authorize & Run Preflight") {
                    Task { await viewModel.runPreflight() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRunPreflight)
            }

            Button("Back to Review") { viewModel.returnToReview() }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let summary = viewModel.resultSummary {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    summary.isVerifiedComplete ? "Verified Complete" : "Verification Incomplete",
                    systemImage: summary.isVerifiedComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.title3.weight(.semibold))

                summaryRows([
                    ("Imported", "\(summary.importedCount)"),
                    ("Skipped existing", "\(summary.skippedExistingCount)"),
                    ("Skipped missing", "\(summary.skippedMissingCount)"),
                    ("Zero-policy skips", "\(summary.skippedZeroPolicyCount)"),
                    ("Authorization blocked", "\(summary.authorizationBlockedCount)"),
                    ("Verified", "\(summary.verifiedCount)"),
                    ("Verification failures", "\(summary.failedVerificationCount)")
                ])

                Text("Run ID: \(summary.runID.uuidString.lowercased())")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                if let auditURL = viewModel.auditBundleURL {
                    ShareLink(item: auditURL) {
                        Label("Export Audit Bundle", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Audit bundle unavailable", systemImage: "doc.badge.ellipsis")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Start New Import") { viewModel.reset() }
                    .buttonStyle(.bordered)
            }
        } else {
            Text("No import result is available.")
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRows(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.subheadline)
    }

    private func dateRange(_ start: String?, _ end: String?) -> String {
        switch (start, end) {
        case let (start?, end?): "\(start) – \(end)"
        case let (start?, nil): start
        case let (nil, end?): end
        default: "Unavailable"
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var safetyFooter: some View {
        Label(
            "Normal imports are append-only. The one-time timestamp-recovery control can delete only legacy BioMIR Backfill-authored historical nutrition samples matching the controlled recovery scope.",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
