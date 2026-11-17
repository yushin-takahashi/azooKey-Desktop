import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

// MARK: - キーイベントの組み立て

private let letterKeyCodes: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46
]

private enum Key {
    case char(Character, KeyEventCore.ModifierFlag = [])
    case space
    case backspace
    case enter
    case escape
    case tab
    case left
    case f7
    case f9
    case f10
    case eisu
    case kana

    var event: KeyEventCore {
        switch self {
        case .char(let c, let modifiers):
            let lower = Character(c.lowercased())
            let keyCode = letterKeyCodes[lower] ?? 0xFFFF
            return KeyEventCore(
                modifierFlags: modifiers,
                characters: String(c),
                charactersIgnoringModifiers: modifiers.contains(.shift) ? String(c) : String(lower),
                keyCode: keyCode
            )
        case .space: return Self.special(" ", keyCode: 49)
        case .backspace: return Self.special("\u{7F}", keyCode: 51)
        case .enter: return Self.special("\r", keyCode: 36)
        case .escape: return Self.special("\u{1B}", keyCode: 53)
        case .tab: return Self.special("\t", keyCode: 48)
        case .left: return Self.special("\u{F702}", keyCode: 123)
        case .f7: return Self.special("\u{F70A}", keyCode: 98)
        case .f9: return Self.special("\u{F70C}", keyCode: 101)
        case .f10: return Self.special("\u{F70D}", keyCode: 109)
        case .eisu: return Self.special("", keyCode: 102)
        case .kana: return Self.special("", keyCode: 104)
        }
    }

    private static func special(_ characters: String, keyCode: UInt16) -> KeyEventCore {
        KeyEventCore(modifierFlags: [], characters: characters, charactersIgnoringModifiers: characters, keyCode: keyCode)
    }
}

private func shift(_ c: Character) -> Key {
    .char(c, [.shift])
}

/// 文字列の各文字を通常のキー入力に変換する（大文字はShift付き）
private func keys(_ string: String) -> [Key] {
    string.map { c in
        if c == " " {
            return .space
        }
        return c.isUppercase ? shift(c) : .char(c)
    }
}

// MARK: - 状態遷移のシミュレーション

private struct StepResult {
    var action: ClientAction
    var callback: ClientActionCallback
}

private func step(
    _ state: InputState,
    _ key: Key,
    inputLanguage: InputLanguage = .japanese,
    liveConversionEnabled: Bool = true,
    enableDebugWindow: Bool = false,
    temporaryEnglishEnabled: Bool = true
) -> StepResult {
    let event = key.event
    let userAction = UserAction.getUserAction(eventCore: event, inputLanguage: inputLanguage, typeBackSlash: false)
    let (action, callback) = state.event(
        eventCore: event,
        userAction: userAction,
        inputLanguage: inputLanguage,
        liveConversionEnabled: liveConversionEnabled,
        enableDebugWindow: enableDebugWindow,
        enableSuggestion: false,
        temporaryEnglishEnabled: temporaryEnglishEnabled
    )
    return StepResult(action: action, callback: callback)
}

private struct Simulation {
    var state: InputState = .none
    /// submitTemporaryEnglish で確定された文字列
    var submitted: [String] = []
    var actions: [ClientAction] = []

    mutating func type(_ keys: [Key], temporaryEnglishEnabled: Bool = true) {
        for key in keys {
            let result = step(self.state, key, temporaryEnglishEnabled: temporaryEnglishEnabled)
            self.actions.append(result.action)
            switch result.action {
            case .submitTemporaryEnglish(let text), .submitTemporaryEnglishAndSelectInputLanguage(let text, _):
                self.submitted.append(text)
            default:
                break
            }
            switch result.callback {
            case .fallthrough:
                break
            case .transition(let newState):
                self.state = newState
            case .basedOnBackspace(_, let ifIsNotEmpty), .basedOnSubmitCandidate(_, let ifIsNotEmpty):
                // このテストでは日本語の未確定文字列の中身を追わないため、空でない側に遷移させる
                self.state = ifIsNotEmpty
            }
        }
    }
}

// MARK: - 依頼書のテストケース 1〜10

@Suite("Shift+英字による一時英字入力")
struct InputStateTemporaryEnglishTests {
    @Test("1: 小文字だけなら通常のローマ字入力")
    func plainRomajiStaysJapanese() {
        var sim = Simulation()
        sim.type(keys("apple"))
        #expect(sim.state == .composing)
        #expect(sim.submitted.isEmpty)
        guard case .appendPieceToMarkedText = sim.actions.first else {
            Issue.record("Expected appendPieceToMarkedText, got \(String(describing: sim.actions.first))")
            return
        }
    }

    @Test("2: Shift+A pple Enter → Apple")
    func capitalizedWord() {
        var sim = Simulation()
        sim.type(keys("Apple"))
        #expect(sim.state == .temporaryEnglish("Apple"))
        sim.type([.enter])
        #expect(sim.submitted == ["Apple"])
        #expect(sim.state == .none)
    }

    @Test("3: すべてShift → APPLE")
    func allCapitalWord() {
        var sim = Simulation()
        sim.type(keys("APPLE") + [.enter])
        #expect(sim.submitted == ["APPLE"])
        #expect(sim.state == .none)
    }

    @Test("4: Shift+S hift Enter → Shift")
    func shiftWord() {
        var sim = Simulation()
        sim.type(keys("Shift") + [.enter])
        #expect(sim.submitted == ["Shift"])
    }

    @Test("5: スペースを挟んで Apple Love")
    func twoWordsWithSpace() {
        var sim = Simulation()
        sim.type(keys("Apple Love") + [.enter])
        #expect(sim.submitted == ["Apple Love"])
    }

    @Test("6: Backspaceで1文字削除 → Aple")
    func backspaceRemovesLastCharacter() {
        var sim = Simulation()
        sim.type(keys("App") + [.backspace] + keys("le") + [.enter])
        #expect(sim.submitted == ["Aple"])
    }

    @Test("7: Escapeでキャンセル")
    func escapeCancels() {
        var sim = Simulation()
        sim.type(keys("Ap") + [.escape])
        #expect(sim.submitted.isEmpty)
        #expect(sim.state == .none)
        guard case .cancelTemporaryEnglish = sim.actions.last else {
            Issue.record("Expected cancelTemporaryEnglish, got \(String(describing: sim.actions.last))")
            return
        }
    }

    @Test("8: Enterで確定後は日本語入力に戻る")
    func returnsToJapaneseAfterEnter() {
        var sim = Simulation()
        sim.type(keys("Apple") + [.enter] + keys("ni"))
        #expect(sim.submitted == ["Apple"])
        #expect(sim.state == .composing)
        guard case .appendPieceToMarkedText = sim.actions.last else {
            Issue.record("Expected appendPieceToMarkedText, got \(String(describing: sim.actions.last))")
            return
        }
    }

    @Test("9: 一時英字が無効なら従来どおりローマ字テーブルに流れる")
    func disabledKeepsLegacyBehavior() {
        var sim = Simulation()
        sim.type(keys("Apple"), temporaryEnglishEnabled: false)
        #expect(sim.state == .composing)
        #expect(sim.submitted.isEmpty)
        #expect(sim.actions.allSatisfy {
            if case .appendPieceToMarkedText = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test("10: 日本語の未確定文字列の後にShift+Aで、表示中の文字列を確定してから英字入力を始める",
          arguments: [InputState.composing, .previewing, .selecting])
    func startFromJapaneseComposition(state: InputState) {
        let result = step(state, shift("A"))
        guard case .commitMarkedText = result.action else {
            Issue.record("Expected commitMarkedText, got \(result.action)")
            return
        }
        guard case .transition(.temporaryEnglish("A")) = result.callback else {
            Issue.record("Expected transition to temporaryEnglish(\"A\"), got \(result.callback)")
            return
        }
    }
}

// MARK: - 開始条件

@Suite("一時英字入力の開始条件")
struct InputStateTemporaryEnglishStartTests {
    @Test("標準ローマ字とAZIKだけで有効。キルスイッチで無効化できる")
    func availability() {
        #expect(InputState.isTemporaryEnglishInputAvailable(inputStyle: .default, enabledByConfig: true))
        #expect(InputState.isTemporaryEnglishInputAvailable(inputStyle: .defaultAZIK, enabledByConfig: true))
        #expect(!InputState.isTemporaryEnglishInputAvailable(inputStyle: .defaultKanaJIS, enabledByConfig: true))
        #expect(!InputState.isTemporaryEnglishInputAvailable(inputStyle: .defaultKanaUS, enabledByConfig: true))
        #expect(!InputState.isTemporaryEnglishInputAvailable(inputStyle: .custom, enabledByConfig: true))
        #expect(!InputState.isTemporaryEnglishInputAvailable(inputStyle: .default, enabledByConfig: false))
    }

    @Test("英語モードでは従来どおり直接入力")
    func englishModeInsertsDirectly() {
        let result = step(.none, shift("A"), inputLanguage: .english)
        guard case .insertWithoutMarkedText("A") = result.action else {
            Issue.record("Expected insertWithoutMarkedText(\"A\"), got \(result.action)")
            return
        }
    }

    @Test("Shift+記号では開始しない")
    func shiftSymbolDoesNotStart() {
        let event = KeyEventCore(modifierFlags: [.shift], characters: "!", charactersIgnoringModifiers: "!", keyCode: 18)
        let userAction = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, typeBackSlash: false)
        let (action, callback) = InputState.none.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false,
            temporaryEnglishEnabled: true
        )
        guard case .appendPieceToMarkedText = action, case .transition(.composing) = callback else {
            Issue.record("Expected Japanese composing, got \(action), \(callback)")
            return
        }
    }

    @Test("Shift以外の修飾キーを含む場合は開始しない",
          arguments: [KeyEventCore.ModifierFlag([.shift, .option]), [.shift, .control], [.shift, .command]])
    func otherModifiersDoNotStart(modifiers: KeyEventCore.ModifierFlag) {
        let result = step(.none, .char("A", modifiers))
        if case .transition(.temporaryEnglish) = result.callback {
            Issue.record("Should not start temporary English with modifiers \(modifiers)")
        }
    }

    @Test("Shiftなしの大文字（Caps Lock相当）では開始しない")
    func uppercaseWithoutShiftDoesNotStart() {
        let result = step(.none, .char("A"))
        if case .transition(.temporaryEnglish) = result.callback {
            Issue.record("Should not start temporary English without shift")
        }
    }

    @Test("選択中のShift+Dはデバッグウィンドウの操作を優先する")
    func debugWindowShortcutHasPriority() {
        let result = step(.selecting, shift("D"), enableDebugWindow: true)
        guard case .disableDebugWindow = result.action else {
            Issue.record("Expected disableDebugWindow, got \(result.action)")
            return
        }
    }

    @Test("変換中のShift+矢印は文節編集のまま")
    func shiftArrowStillEditsSegment() {
        let event = KeyEventCore(modifierFlags: [.shift], characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", keyCode: 124)
        let userAction = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, typeBackSlash: false)
        let (action, _) = InputState.composing.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false,
            temporaryEnglishEnabled: true
        )
        guard case .editSegment(1) = action else {
            Issue.record("Expected editSegment(1), got \(action)")
            return
        }
    }
}

// MARK: - 一時英字入力中のキー操作

@Suite("一時英字入力中のキー操作")
struct InputStateTemporaryEnglishEditingTests {
    @Test("1文字の状態でBackspaceすると一時英字入力を終える")
    func backspaceOnLastCharacterExits() {
        var sim = Simulation()
        sim.type(keys("A") + [.backspace])
        #expect(sim.state == .none)
        #expect(sim.submitted.isEmpty)
        // 次の小文字は日本語として入る
        sim.type(keys("a"))
        #expect(sim.state == .composing)
    }

    @Test("記号と数字は半角のまま追加する")
    func punctuationAndDigitsStayHalfWidth() {
        let period = KeyEventCore(modifierFlags: [], characters: ".", charactersIgnoringModifiers: ".", keyCode: 47)
        let comma = KeyEventCore(modifierFlags: [], characters: ",", charactersIgnoringModifiers: ",", keyCode: 43)
        let minus = KeyEventCore(modifierFlags: [], characters: "-", charactersIgnoringModifiers: "-", keyCode: 27)
        let three = KeyEventCore(modifierFlags: [], characters: "3", charactersIgnoringModifiers: "3", keyCode: 20)
        var state = InputState.temporaryEnglish("A")
        for event in [period, comma, minus, three] {
            let userAction = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, typeBackSlash: false)
            let (_, callback) = state.event(
                eventCore: event,
                userAction: userAction,
                inputLanguage: .japanese,
                liveConversionEnabled: true,
                enableDebugWindow: false,
                enableSuggestion: false,
                temporaryEnglishEnabled: true
            )
            guard case .transition(let next) = callback else {
                Issue.record("Expected transition, got \(callback)")
                return
            }
            state = next
        }
        #expect(state == .temporaryEnglish("A.,-3"))
    }

    @Test("全角スペース設定でもスペースは半角")
    func spaceIsAlwaysHalfWidth() {
        let event = KeyEventCore(modifierFlags: [], characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let (action, callback) = InputState.temporaryEnglish("A").event(
            eventCore: event,
            userAction: .space(prefersFullWidthWhenInput: true),
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false,
            temporaryEnglishEnabled: true
        )
        guard case .appendToTemporaryEnglish(" ") = action, case .transition(.temporaryEnglish("A ")) = callback else {
            Issue.record("Expected half-width space, got \(action), \(callback)")
            return
        }
    }

    @Test("F10は半角、F9は全角で確定する")
    func functionKeysSubmit() {
        var sim = Simulation()
        sim.type(keys("Mac") + [.f10])
        #expect(sim.submitted == ["Mac"])
        #expect(sim.state == .none)

        var sim9 = Simulation()
        sim9.type(keys("Mac") + [.f9])
        #expect(sim9.submitted == ["Ｍａｃ"])
    }

    @Test("F7は何もしない")
    func f7DoesNothing() {
        var sim = Simulation()
        sim.type(keys("Mac") + [.f7])
        #expect(sim.state == .temporaryEnglish("Mac"))
        #expect(sim.submitted.isEmpty)
    }

    @Test("かなキーは確定して日本語に戻る")
    func kanaKeySubmits() {
        var sim = Simulation()
        sim.type(keys("Mac") + [.kana])
        #expect(sim.submitted == ["Mac"])
        #expect(sim.state == .none)
    }

    @Test("英数キーは確定して英語モードへ移る")
    func eisuKeySubmitsAndSwitches() {
        let result = step(.temporaryEnglish("Mac"), .eisu)
        guard case .submitTemporaryEnglishAndSelectInputLanguage("Mac", .english) = result.action,
              case .transition(.none) = result.callback else {
            Issue.record("Expected submit and switch to English, got \(result.action), \(result.callback)")
            return
        }
    }

    @Test("Tab・矢印は消費し、未確定の英字を保持する", arguments: [Key.tab, .left])
    fileprivate func navigationIsConsumed(key: Key) {
        let result = step(.temporaryEnglish("Mac"), key)
        guard case .consume = result.action, case .fallthrough = result.callback else {
            Issue.record("Expected consume, got \(result.action), \(result.callback)")
            return
        }
    }

    @Test("Option+Enterでも確定する（ホストアプリに素通りしない）")
    func optionEnterSubmits() {
        let event = KeyEventCore(modifierFlags: [.option], characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let (action, callback) = InputState.temporaryEnglish("Mac").event(
            eventCore: event,
            userAction: .enter,
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false,
            temporaryEnglishEnabled: true
        )
        guard case .submitTemporaryEnglish("Mac") = action, case .transition(.none) = callback else {
            Issue.record("Expected submit, got \(action), \(callback)")
            return
        }
    }

    @Test("未定義のCtrl+キーは消費する")
    func unknownControlIsConsumed() {
        let event = KeyEventCore(modifierFlags: [.control], characters: "\u{11}", charactersIgnoringModifiers: "q", keyCode: 12)
        let userAction = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, typeBackSlash: false)
        let (action, _) = InputState.temporaryEnglish("Mac").event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false,
            temporaryEnglishEnabled: true
        )
        guard case .consume = action else {
            Issue.record("Expected consume, got \(action)")
            return
        }
    }

    @Test("Cmd+キーはホストアプリに渡し、状態を保持する")
    func commandFallsThrough() {
        let result = step(.temporaryEnglish("Mac"), .char("v", [.command]))
        guard case .fallthrough = result.action, case .fallthrough = result.callback else {
            Issue.record("Expected fallthrough, got \(result.action), \(result.callback)")
            return
        }
    }

    @Test("Shift+英字を続けても大文字として追加するだけ")
    func shiftInsideTemporaryEnglishAppends() {
        let result = step(.temporaryEnglish("Mac"), shift("B"))
        guard case .appendToTemporaryEnglish("B") = result.action,
              case .transition(.temporaryEnglish("MacB")) = result.callback else {
            Issue.record("Expected append, got \(result.action), \(result.callback)")
            return
        }
    }
}

// MARK: - 表示

@MainActor
@Test("一時英字入力中は入力済みの英字をそのまま未確定文字列として示し、候補ウィンドウは出さない")
func temporaryEnglishMarkedText() {
    let manager = SegmentsManager(
        kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
    let markedText = manager.getCurrentMarkedText(inputState: .temporaryEnglish("Apple Love"))
    #expect(markedText.map(\.content).joined() == "Apple Love")
    #expect(manager.isEmpty)
    guard case .hidden = manager.getCurrentCandidateWindow(inputState: .temporaryEnglish("Apple Love")) else {
        Issue.record("Candidate window should be hidden")
        return
    }
}
