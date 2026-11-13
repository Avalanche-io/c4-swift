import Testing

@Test(.disabled("probe static skip"))
func probeDisabled() {}

@Test(.enabled(if: false, "probe conditional skip"))
func probeConditional() {}

@Suite(.disabled("probe suite skip"))
struct ProbeSuite {
    @Test func inner() {}
}

#if compiler(>=6.3)
@Test func probeCancel() throws {
    try Test.cancel("probe runtime cancel")
}
#endif
