import Foundation
import Testing
@testable import BugVoiceMac

struct SecureFocusPolicyTests {
    private func decide(
        trusted: Bool = true, readable: Bool = true,
        role: AttributeRead = .value("AXTextField"), subrole: AttributeRead = .absent,
        input: SecureInputState = .off, front: pid_t? = 100
    ) -> Bool {
        SecureFocusPolicy.isSecure(axTrusted: trusted, focusedElementReadable: readable,
                                   role: role, subrole: subrole, secureInput: input, frontmostPID: front)
    }

    @Test func plainFieldIsNotSecure() { #expect(!decide()) }
    @Test func absentRoleAndSubroleIsNotSecure() { #expect(!decide(role: .absent, subrole: .absent)) }
    @Test func secureSubroleIsSecure() { #expect(decide(subrole: .value("AXSecureTextField"))) }
    @Test func secureRoleIsSecure() { #expect(decide(role: .value("AXSecureTextField"))) }
    @Test func untrustedFailsClosed() { #expect(decide(trusted: false)) }
    // Electron apps (VS Code) hide their focused element; a real password
    // field there turns on Secure Event Input, so off means paste.
    @Test func unreadableFocusWithoutSecureInputIsNotSecure() { #expect(!decide(readable: false, role: .failed, subrole: .failed)) }
    @Test func unreadableFocusWithSecureInputElsewhereFailsClosed() { #expect(decide(readable: false, role: .failed, subrole: .failed, input: .owner(7))) }
    @Test func unreadableFocusUntrustedFailsClosed() { #expect(decide(trusted: false, readable: false)) }
    @Test func failedSubroleReadFailsClosed() { #expect(decide(subrole: .failed)) }
    @Test func failedRoleReadFailsClosed() { #expect(decide(role: .failed)) }
    @Test func secureInputOwnedByFrontmostIsSecure() { #expect(decide(input: .owner(100))) }
    @Test func secureInputOwnedByOtherAppIsNotSecure() { #expect(!decide(input: .owner(7))) }
    @Test func unknownSecureInputOwnerFailsClosed() { #expect(decide(input: .ownerUnknown)) }
}
