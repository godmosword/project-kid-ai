import SwiftUI

/// 依全部測試變因分組彙總（CRITICAL-6），只顯示次數、比例與延遲，供大人抄進報告；不存檔。
struct SummaryView: View {
    @Bindable var model: SpikeModel

    private struct Group: Identifiable {
        let id: String
        let rows: [TrialResult]
    }

    private var groups: [Group] {
        Dictionary(grouping: model.results) { $0.settings.groupKey(includePhrase: model.includePhraseInSummary) }
            .map { Group(id: $0.key, rows: $0.value) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        List {
            Toggle("按句子分開", isOn: $model.includePhraseInSummary)
            ForEach(groups) { group in
                Section(group.id) { rows(for: group.rows) }
            }
            Section {
                Button("清除全部", role: .destructive, action: model.clearResults)
            }
        }
        .navigationTitle("彙總")
    }

    @ViewBuilder
    private func rows(for all: [TrialResult]) -> some View {
        let rows = all.filter { !$0.outcome.isExcludedFromRates }
        let count = rows.count
        let keyword = rows.filter { $0.outcome == .keyword }.count
        let voiceOnly = rows.filter { $0.outcome == .voiceOnly }.count
        let content = all.first?.settings.content
        let feedback = rows.compactMap(\.feedbackAfterSilenceMs)
        LabeledContent("有效次數（不含不可用、中斷）", value: "\(count)／\(all.count)")
        if content?.isNegative == true {
            LabeledContent("關鍵詞誤觸發", value: "\(keyword)（\(percent(keyword, count))）")
            if content?.countsForVoiceFalseTrigger == true {
                LabeledContent("出聲誤觸發", value: "\(keyword + voiceOnly)（\(percent(keyword + voiceOnly, count))）")
            }
        } else {
            LabeledContent("算完成", value: "\(keyword + voiceOnly)（\(percent(keyword + voiceOnly, count))）")
            LabeledContent("關鍵詞／只靠出聲", value: "\(keyword)／\(voiceOnly)")
        }
        LabeledContent("都沒有", value: "\(rows.filter { $0.outcome == .nothing }.count)")
        LabeledContent("不可用／中斷", value: "\(all.filter(isUnavailable).count)／\(all.filter(isInterrupted).count)")
        LabeledContent("撞上限", value: "\(rows.filter { $0.endReason == .timeout }.count)")
        LabeledContent("講完後出現鼓勵 p50／p90", value: percentiles(feedback.filter { $0 >= 0 }))
        LabeledContent("還在說就被鼓勵", value: "\(feedback.filter { $0 < 0 }.count)（\(percent(feedback.filter { $0 < 0 }.count, feedback.count))）")
        LabeledContent("開始收音 p50／p90", value: percentiles(rows.compactMap(\.captureDelayMs)))
        LabeledContent("開口時間 p50／p90", value: percentiles(rows.compactMap(\.voiceOnsetMs)))
        LabeledContent("背景音量中位數", value: median(rows.compactMap(\.noiseMedianDB)).map { "\($0) dB" } ?? "—")
        LabeledContent("每段音訊", value: median(rows.compactMap(\.bufferMs)).map { "\($0) ms" } ?? "—")
        ForEach(counts(rows.compactMap(\.matchedKeywordIndex).map { "第 \($0 + 1) 個詞" }), id: \.0) { label, times in
            LabeledContent("命中 \(label)", value: "\(times)")
        }
        ForEach(counts(all.compactMap(\.errorCode)), id: \.0) { code, times in
            LabeledContent("錯誤 \(code)", value: "\(times)")
        }
    }

    private func isUnavailable(_ row: TrialResult) -> Bool {
        if case .unavailable = row.outcome { return true }
        return false
    }

    private func isInterrupted(_ row: TrialResult) -> Bool {
        if case .interrupted = row.outcome { return true }
        return false
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "—" : "\(part * 100 / whole)%"
    }

    private func percentiles(_ values: [Int]) -> String {
        guard let p50 = Percentile.value(values, 0.5), let p90 = Percentile.value(values, 0.9) else { return "—" }
        return "\(p50)／\(p90) ms"
    }

    private func median(_ values: [Int]) -> Int? {
        Percentile.value(values, 0.5)
    }

    private func counts(_ labels: [String]) -> [(String, Int)] {
        Dictionary(grouping: labels) { $0 }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0 < $1.0 }
    }
}
