# 觀察員選單

試玩時給大人用的工具，只在 Debug build 裡有；Release build 完全沒有入口、選單與關卡資訊。在單元裡，兩指同時按住進度點上方 3 秒，會跳出「觀察員」選單：可以打開「顯示關卡資訊」（beat id、嘗試次數、秒數，顯示在進度點下方）、跳到任一關、重玩本單元，最下面提示換下一位孩子時把 App 滑掉重開。選單不保存任何資料。

## Sub-features

- `observer-open`：兩指長按進度點上方 3 秒 → 跳出「觀察員」選單；單指按不會開。
- `observer-debug-info`：「顯示關卡資訊」開關 → 進度點下方出現 beat id｜嘗試次數｜秒數。
- `observer-jump`：「跳到」清單點一關 → 關閉選單並跳到那一關。
- `observer-restart`：「重玩本單元」→ 回到第 1 關。
- `observer-release-absent`：Release build 沒有這個入口。

## How to get to it (user POV)

- Debug build，在任一單元裡，兩指同時按住畫面上方進度點的上方 3 秒（`two-finger-hold`）。
- 只給試玩的大人用；孩子的路徑不會碰到。

## Driving it with control-kidsai

Preconditions:

- baseline（Debug build）；`doctor` 通過。

- **打開選單（observer-open）。** `verified-unreachable`：XCUITest 沒有兩指長按（只有兩指輕點），`control-kidsai` 也沒有多指手勢。前提：需要人手在模擬器（Option＋拖曳出兩指）或實機上操作。
- **關卡資訊、跳關、重玩（observer-debug-info、observer-jump、observer-restart）。** 同上，要先打開選單；`verified-unreachable`。
- **Release 沒有入口（observer-release-absent）。** 用原始碼確認：入口與選單都包在 `#if DEBUG` 裡（`app/KidsAI/UI/ObserverMenu.swift`）。這是 source 覆蓋，不是 live 證明。

## Gotchas

- 入口是透明的，而且不在 VoiceOver 裡（`accessibilityHidden`），畫面上看不到、無障礙元素樹裡也找不到。
- 「跳到」和啟動參數 `--beat` 效果相近，但它是大人在畫面上操作；兩者都不是孩子路徑的證明。
- 換下一位孩子要把 App 滑掉重開：進度只在記憶體。
