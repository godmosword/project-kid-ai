import SwiftUI

/// 測試用畫面（只給大人）。只顯示符合與否、延遲與可用性，不顯示任何辨識文字。
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var confirmDownload = false

    var body: some View {
        NavigationStack {
            Form {
                runSection
                if model.showSayTogether { sayTogetherSection }
                settingsSection
                availabilitySection
                NavigationLink("彙總（\(model.results.count) 次）") {
                    SummaryView(model: model)
                }
            }
            .navigationTitle("ASR 測試（大人專用）")
            .task { await model.refreshAvailability() }
            .confirmationDialog("下載 zh-TW 語音模型？", isPresented: $confirmDownload, titleVisibility: .visible) {
                Button("下載（會向 Apple 連線）") {
                    Task { await model.downloadModel() }
                }
            } message: {
                Text("這是 spike 限定的網路例外：只會向 Apple 下載語音模型，不會送出任何聲音。正式 App 不會這樣做。")
            }
        }
    }

    private var runSection: some View {
        Section("執行") {
            Text(model.settingsBanner)
                .font(.headline.monospaced())
            Text("這一組已做 \(model.currentGroupCount) 次")
                .font(.subheadline)
            Button(model.isRunning ? "聆聽中…" : "開始一次") {
                Task { await model.runTrial() }
            }
            .disabled(model.isRunning || model.isDownloading)
            .font(.title2.bold())
            ProgressView(value: Double(max(0, model.levelDB + 80)), total: 80) {
                Text("音量")
            }
            if let outcome = model.lastOutcome {
                LabeledContent("上一次", value: outcome.label)
            }
            if let blocked = model.blockedReason {
                Text(blocked).foregroundStyle(.red)
            }
            Button("刪除上一筆", role: .destructive, action: model.deleteLast)
                .disabled(model.isRunning || model.results.isEmpty)
        }
    }

    private var sayTogetherSection: some View {
        Section("退路（孩子會看到的畫面）") {
            Text(SpikeModel.sayTogetherLine)
                .font(.title3)
        }
    }

    private var settingsSection: some View {
        Section("設定") {
            Picker("路徑", selection: $model.path) {
                ForEach(SpikePath.allCases) { Text($0.title).tag($0) }
            }
            Picker("句子", selection: $model.phrase) {
                ForEach(Phrase.catalog) { Text($0.line).tag($0) }
            }
            Picker("環境", selection: $model.environment) {
                ForEach(TrialEnvironment.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("說話內容", selection: $model.content) {
                ForEach(SpeechContent.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("講完後停頓", selection: $model.pauseSeconds) {
                ForEach(SpikeModel.pauseOptions, id: \.self) { Text(String(format: "%.1f 秒", $0)).tag($0) }
            }
            Picker("總長上限", selection: $model.maxSeconds) {
                ForEach(SpikeModel.maxOptions, id: \.self) { Text("\(Int($0)) 秒").tag($0) }
            }
            Picker("出聲門檻", selection: $model.vadThresholdDB) {
                ForEach(SpikeModel.thresholdOptions, id: \.self) { Text("\($0) dB").tag($0) }
            }
            Picker("音訊模式", selection: $model.sessionMode) {
                ForEach(SessionMode.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("先播提示語音", isOn: $model.playPrompt)
            Toggle("飛航模式中（手動確認）", isOn: $model.airplaneMode)
        }
        .disabled(model.isRunning)
    }

    private var availabilitySection: some View {
        Section("可用性") {
            ForEach(model.availability, id: \.self) { Text($0).font(.footnote) }
            Button("重新檢查") {
                Task { await model.refreshAvailability() }
            }
            .disabled(model.isRunning)
            if model.canDownload {
                Button("下載 zh-TW 模型（spike 限定，會連網）") { confirmDownload = true }
            }
            if let status = model.downloadStatus {
                Text(status).font(.footnote)
            }
        }
    }
}
