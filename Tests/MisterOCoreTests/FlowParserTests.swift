import Testing
@testable import MisterOCore

struct FlowParserTests {
    private let parser = FlowParser()

    @Test func parsesAllCommands() throws {
        let steps = try parser.parse("""
        tap: "login_button"
        type: "email_field" -> "test@example.com"
        wait: 2
        assertVisible: "welcome_label"
        assertNotVisible: error_label
        AssertEnabled: save_button
        assertDisabled: login_button
        """)

        #expect(steps.map(\.command) == [
            .tap("login_button"),
            .typeText("email_field", text: "test@example.com"),
            .wait(seconds: 2),
            .assertVisible("welcome_label"),
            .assertNotVisible("error_label"),
            .assertEnabled("save_button"),
            .assertDisabled("login_button"),
        ])
        #expect(steps.map(\.line) == [1, 2, 3, 4, 5, 6, 7])
        #expect(steps.map(\.id) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func skipsCommentsAndBlankLinesButKeepsLineNumbers() throws {
        let steps = try parser.parse("""
        # giriş akışı

        - tap: "Giriş Yap"   # YAML listesi + satır sonu yorumu
        TAP: Devam
        """)

        #expect(steps.map(\.command) == [.tap("Giriş Yap"), .tap("Devam")])
        #expect(steps.map(\.line) == [3, 4])
        #expect(steps[0].source == "- tap: \"Giriş Yap\"   # YAML listesi + satır sonu yorumu")
    }

    @Test func acceptsBareSmartAndEscapedValues() throws {
        let steps = try parser.parse("""
        tap: Hesabım
        tap: “Kaydet”
        type: ‘note’ → 'it\\'s "fine"'
        type: search -> a->b
        type: "email" -> ""
        wait: 1,5
        """)

        #expect(steps.map(\.command) == [
            .tap("Hesabım"),
            .tap("Kaydet"),
            .typeText("note", text: "it's \"fine\""),
            .typeText("search", text: "a->b"),
            .typeText("email", text: ""),
            .wait(seconds: 1.5),
        ])
    }

    @Test func handlesWindowsLineEndings() throws {
        let steps = try parser.parse("tap: a\r\nwait: 1\r\n")
        #expect(steps.map(\.command) == [.tap("a"), .wait(seconds: 1)])
    }

    @Test func collectsEveryIssueWithLineNumbers() {
        let script = """
        tap: "ok"
        tapp: "typo"
        type: "email" "eksik ok"
        wait: soon
        assertVisible: "kapanmamış
        tap:
        tap: "a" "b"
        """

        #expect(throws: FlowParseError.self) { try parser.parse(script) }
        do {
            _ = try parser.parse(script)
        } catch {
            #expect(error.issues.map(\.line) == [2, 3, 4, 5, 6, 7])
            #expect(error.issues[0].message.contains("Unknown command 'tapp'"))
            #expect(error.issues[1].message.contains("Missing '->'"))
            #expect(error.issues[2].message.contains("Invalid duration"))
            #expect(error.issues[3].message.contains("Unclosed quote"))
            #expect(error.issues[4].message.contains("Missing value"))
            #expect(error.issues[5].message.contains("Unexpected content"))
        }
    }

    @Test func rejectsEmptyScriptAndOutOfRangeWait() {
        #expect(throws: FlowParseError(issues: [.init(line: nil, message: "There are no steps to run.")])) {
            try parser.parse("# sadece yorum\n\n")
        }
        #expect(throws: FlowParseError.self) { try parser.parse("wait: -1") }
        #expect(throws: FlowParseError.self) { try parser.parse("wait: 301") }
        #expect(throws: FlowParseError.self) { try parser.parse("tap: \"\"") }
    }

    @Test func quoteRoundTrips() throws {
        let tricky = "say \"hi\" \\ -> # not a comment"
        let steps = try parser.parse("tap: \(FlowParser.quote(tricky))")
        #expect(steps.first?.command == .tap(ElementSelector(tricky)))
    }

    @Test func parsesTextScrollAndBack() throws {
        let steps = try parser.parse("""
        assertText: welcome_label -> "Hoş geldin"
        scroll: down
        scroll: "settings_list" -> LEFT
        back
        - back:   # sheet'i kapat
        """)

        #expect(steps.map(\.command) == [
            .assertText("welcome_label", text: "Hoş geldin"),
            .scroll(.down, in: nil),
            .scroll(.left, in: "settings_list"),
            .back,
            .back,
        ])
    }

    @Test func rejectsBadDirectionsAndMissingArrows() {
        #expect(throws: FlowParseError.self) { try parser.parse("scroll: sideways") }
        #expect(throws: FlowParseError.self) { try parser.parse("assertText: welcome_label") }
        #expect(throws: FlowParseError.self) { try parser.parse("backwards") }
    }

    @Test func fillsVariables() throws {
        let parser = FlowParser(variables: ["Test hesabı e-postası": "qa@firma.com", "PIN": "1234"])
        let steps = try parser.parse("""
        type: email_field -> {{Test hesabı e-postası}}
        type: "pin_field" -> "{{ pin }}-{{PIN}}"
        """)

        #expect(steps.map(\.command) == [
            .typeText("email_field", text: "qa@firma.com"),
            .typeText("pin_field", text: "1234-1234"),
        ])
        #expect(steps[0].source == "type: email_field -> {{Test hesabı e-postası}}")
    }

    @Test func reportsUnknownAndUnclosedVariables() {
        let known = FlowParser(variables: ["PIN": "1234"])
        #expect(throws: FlowParseError(issues: [.init(line: 1, message: "Unknown variable {{Şifre}}. Known → PIN")])) {
            try known.parse("type: pin_field -> {{Şifre}}")
        }
        #expect(throws: FlowParseError(issues: [
            .init(line: 1, message: "Unknown variable {{PIN}}. Add it to testData when installing Mister-O."),
        ])) {
            try FlowParser().parse("type: pin_field -> {{PIN}}")
        }
        #expect(throws: FlowParseError(issues: [.init(line: 1, message: "Unclosed variable: '{{' needs '}}'.")])) {
            try known.parse("type: pin_field -> {{PIN")
        }
    }

}
