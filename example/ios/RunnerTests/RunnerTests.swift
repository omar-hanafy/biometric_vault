// Shared test suite for the Darwin (iOS + macOS) implementation of
// biometric_vault. The macOS RunnerTests.swift is a symlink to this file,
// mirroring how macos/Classes/BiometricVaultImpl.swift is shared.
//
// These tests exercise BiometricVaultImpl through its injectable seams:
// - KeychainClient: fake keychain, no real Security framework item storage.
// - contextFactory: LAContext subclass to simulate LocalAuthentication.
// - accessControlFactory: records SecAccessControlCreateFlags choices.
// - now: injectable clock for context reuse expiry.

import XCTest
import LocalAuthentication
@testable import biometric_vault

// MARK: - Test doubles

/// Error object produced by the storageError factory in tests
/// (stands in for FlutterError, which is what the plugin shims produce).
private struct TestPluginError {
  let code: String
  let message: String?
  let details: Any?
}

private final class FakeKeychain: KeychainClient {
  var copyMatchingResult: (status: OSStatus, item: AnyObject?) = (errSecItemNotFound, nil)
  var addResult: OSStatus = errSecSuccess
  var updateResult: OSStatus = errSecSuccess
  var deleteResult: OSStatus = errSecSuccess

  private(set) var copyMatchingQueries: [[String: Any]] = []
  private(set) var addedAttributes: [[String: Any]] = []
  private(set) var updateCalls: [(query: [String: Any], attributes: [String: Any])] = []
  private(set) var deleteQueries: [[String: Any]] = []

  func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: AnyObject?) {
    copyMatchingQueries.append(query)
    return copyMatchingResult
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    addedAttributes.append(attributes)
    return addResult
  }

  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    updateCalls.append((query: query, attributes: attributes))
    return updateResult
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    deleteQueries.append(query)
    return deleteResult
  }
}

private final class ThreadProbeKeychain: KeychainClient {
  private let onKeychainCall: (Bool) -> Void

  init(onKeychainCall: @escaping (Bool) -> Void) {
    self.onKeychainCall = onKeychainCall
  }

  func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: AnyObject?) {
    onKeychainCall(Thread.isMainThread)
    return (errSecItemNotFound, nil)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    onKeychainCall(Thread.isMainThread)
    return errSecSuccess
  }

  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    onKeychainCall(Thread.isMainThread)
    return errSecSuccess
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    onKeychainCall(Thread.isMainThread)
    return errSecSuccess
  }
}

private final class FakeLAContext: LAContext {
  var canEvaluateResult = true
  var canEvaluateError: NSError?
  private(set) var evaluatedPolicies: [LAPolicy] = []

  var biometryTypeOverride: LABiometryType = .none
  override var biometryType: LABiometryType { biometryTypeOverride }

  var evaluateResult = true
  var evaluateError: NSError?
  private(set) var evaluateCalls: [(policy: LAPolicy, reason: String)] = []

  private var reuseDuration: TimeInterval = 0
  override var touchIDAuthenticationAllowableReuseDuration: TimeInterval {
    get { reuseDuration }
    set { reuseDuration = newValue }
  }

  override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
    evaluatedPolicies.append(policy)
    if let canEvaluateError, !canEvaluateResult {
      error?.pointee = canEvaluateError
    }
    return canEvaluateResult
  }

  override func evaluatePolicy(
    _ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void
  ) {
    evaluateCalls.append((policy: policy, reason: localizedReason))
    reply(evaluateResult, evaluateError)
  }
}

private func laError(_ code: Int) -> NSError {
  NSError(domain: LAErrorDomain, code: code)
}

private func keys(_ secKeys: [CFString]) -> Set<String> {
  Set(secKeys.map { $0 as String })
}

// MARK: - Test case

final class RunnerTests: XCTestCase {

  private let notImplemented = NSObject()
  private var keychain = FakeKeychain()
  private var contexts: [FakeLAContext] = []
  private var contextFactoryCallCount = 0
  private var contextFactoryThreadWasMain: [Bool] = []
  private var recordedAccessControlFlags: [SecAccessControlCreateFlags] = []
  private var currentDate = Date(timeIntervalSince1970: 1_000_000)

  override func setUp() {
    super.setUp()
    keychain = FakeKeychain()
    contexts = []
    contextFactoryCallCount = 0
    contextFactoryThreadWasMain = []
    recordedAccessControlFlags = []
    currentDate = Date(timeIntervalSince1970: 1_000_000)
  }

  private func makeImpl(
    keychain keychainOverride: KeychainClient? = nil,
    nextContext: (() -> FakeLAContext)? = nil,
    accessControlFactory: ((SecAccessControlCreateFlags) -> SecAccessControl?)? = nil
  ) -> BiometricVaultImpl {
    BiometricVaultImpl(
      storageError: { code, message, details in
        TestPluginError(code: code, message: message, details: details)
      },
      storageMethodNotImplemented: notImplemented,
      keychain: keychainOverride ?? keychain,
      contextFactory: { [self] in
        contextFactoryCallCount += 1
        contextFactoryThreadWasMain.append(Thread.isMainThread)
        let context = nextContext?() ?? FakeLAContext()
        contexts.append(context)
        return context
      },
      accessControlFactory: accessControlFactory ?? { [self] flags in
        recordedAccessControlFlags.append(flags)
        var error: Unmanaged<CFError>?
        return SecAccessControlCreateWithFlags(
          nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, &error)
      },
      now: { [self] in currentDate }
    )
  }

  @discardableResult
  private func invoke(_ impl: BiometricVaultImpl, _ method: String, _ arguments: Any?) -> Any? {
    let resultArrived = expectation(description: "result for \(method)")
    var captured: Any?
    impl.handle(StorageMethodCall(method: method, arguments: arguments)) { value in
      captured = value
      resultArrived.fulfill()
    }
    wait(for: [resultArrived], timeout: 5)
    return captured
  }

  private func options(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = [
      "authenticationRequired": true,
      "darwinBiometricOnly": true,
    ]
    result.merge(overrides) { _, new in new }
    return result
  }

  private func promptArgs(
    _ name: String = "store",
    save: String = "Save prompt",
    access: String = "Access prompt",
    extra: [String: Any] = [:]
  ) -> [String: Any] {
    var result: [String: Any] = [
      "name": name,
      "iosPromptInfo": ["saveTitle": save, "accessTitle": access],
    ]
    result.merge(extra) { _, new in new }
    return result
  }

  private func initStore(
    _ impl: BiometricVaultImpl, _ name: String = "store",
    options overrides: [String: Any] = [:],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let value = invoke(impl, "init", ["name": name, "options": options(overrides)])
    XCTAssertEqual(value as? Bool, true, "expected init to create store", file: file, line: line)
  }

  private func assertError(
    _ value: Any?, code: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let error = value as? TestPluginError else {
      XCTFail("Expected TestPluginError(\(code)) but got \(String(describing: value))",
              file: file, line: line)
      return
    }
    XCTAssertEqual(error.code, code, file: file, line: line)
  }

  // MARK: Method routing and argument validation

  func testUnknownMethodReturnsNotImplementedSentinel() {
    let impl = makeImpl()
    let value = invoke(impl, "definitelyNotAMethod", nil)
    XCTAssertTrue(value as AnyObject === notImplemented)
  }

  func testCanAuthenticateWithoutOptionsReturnsInvalidArguments() {
    let impl = makeImpl()
    assertError(invoke(impl, "canAuthenticate", [String: Any]()), code: "InvalidArguments")
  }

  func testInitWithoutNameReturnsInvalidArguments() {
    let impl = makeImpl()
    assertError(invoke(impl, "init", ["options": options()]), code: "InvalidArguments")
  }

  func testInitWithWrongNameTypeReturnsInvalidArguments() {
    let impl = makeImpl()
    assertError(invoke(impl, "init", ["name": 42, "options": options()]),
                code: "InvalidArguments")
  }

  func testReadWithoutPromptInfoReturnsInvalidArguments() {
    let impl = makeImpl()
    initStore(impl)
    assertError(invoke(impl, "read", ["name": "store"]), code: "InvalidArguments")
  }

  func testWriteWithoutContentReturnsInvalidArguments() {
    let impl = makeImpl()
    initStore(impl)
    assertError(invoke(impl, "write", promptArgs()), code: "InvalidArguments")
  }

  func testReadOnUninitializedStoreReturnsNoSuchStorage() {
    let impl = makeImpl()
    assertError(invoke(impl, "read", promptArgs("missing")), code: "NoSuchStorage")
  }

  // MARK: Store lifecycle

  func testInitCreatesStoreAndSecondInitReturnsFalse() {
    let impl = makeImpl()
    initStore(impl)
    let second = invoke(impl, "init", ["name": "store", "options": options()])
    XCTAssertEqual(second as? Bool, false)
  }

  func testForceInitOnExistingStoreReturnsAlreadyInitialized() {
    let impl = makeImpl()
    initStore(impl)
    let value = invoke(
      impl, "init", ["name": "store", "options": options(), "forceInit": true])
    assertError(value, code: "AlreadyInitialized")
  }

  func testDisposeRemovesStoreAndAllowsReinit() {
    let impl = makeImpl()
    initStore(impl)
    XCTAssertEqual(invoke(impl, "dispose", ["name": "store"]) as? Bool, true)
    initStore(impl)
  }

  func testDisposeOfUnknownStoreReturnsNoSuchStorage() {
    let impl = makeImpl()
    assertError(invoke(impl, "dispose", ["name": "nope"]), code: "NoSuchStorage")
  }

  // MARK: canAuthenticate

  private func canAuthenticateResult(
    canEvaluate: Bool, errorCode: Int? = nil, biometricOnly: Bool = true
  ) -> (result: Any?, context: FakeLAContext) {
    let context = FakeLAContext()
    context.canEvaluateResult = canEvaluate
    if let errorCode {
      context.canEvaluateError = laError(errorCode)
    }
    let impl = makeImpl(nextContext: { context })
    let value = invoke(
      impl, "canAuthenticate",
      ["options": options(["darwinBiometricOnly": biometricOnly])])
    return (value, context)
  }

  func testCanAuthenticateSuccessUsesBiometricsOnlyPolicy() {
    let (value, context) = canAuthenticateResult(canEvaluate: true)
    XCTAssertEqual(value as? String, "Success")
    XCTAssertEqual(context.evaluatedPolicies, [.deviceOwnerAuthenticationWithBiometrics])
  }

  func testCanAuthenticateWithoutBiometricOnlyUsesDeviceOwnerPolicy() {
    let (value, context) = canAuthenticateResult(canEvaluate: true, biometricOnly: false)
    XCTAssertEqual(value as? String, "Success")
    XCTAssertEqual(context.evaluatedPolicies, [.deviceOwnerAuthentication])
  }

  func testCanAuthenticateMapsBiometryNotEnrolled() {
    let (value, _) = canAuthenticateResult(
      canEvaluate: false, errorCode: LAError.biometryNotEnrolled.rawValue)
    XCTAssertEqual(value as? String, "ErrorNoBiometricEnrolled")
  }

  func testCanAuthenticateMapsPasscodeNotSet() {
    let (value, _) = canAuthenticateResult(
      canEvaluate: false, errorCode: LAError.passcodeNotSet.rawValue)
    XCTAssertEqual(value as? String, "ErrorPasscodeNotSet")
  }

  func testCanAuthenticateMapsBiometryNotAvailable() {
    let (value, _) = canAuthenticateResult(
      canEvaluate: false, errorCode: LAError.biometryNotAvailable.rawValue)
    XCTAssertEqual(value as? String, "ErrorHwUnavailable")
  }

  func testCanAuthenticateMapsBiometryLockoutToLockedOut() {
    let (value, _) = canAuthenticateResult(
      canEvaluate: false, errorCode: LAError.biometryLockout.rawValue)
    XCTAssertEqual(value as? String, "ErrorLockedOut")
  }

  func testCanAuthenticateMapsUnknownFailureToErrorUnknown() {
    let (value, _) = canAuthenticateResult(
      canEvaluate: false, errorCode: LAError.invalidContext.rawValue)
    XCTAssertEqual(value as? String, "ErrorUnknown")
  }

  func testCanAuthenticateWithoutErrorObjectReturnsErrorUnknown() {
    let (value, _) = canAuthenticateResult(canEvaluate: false)
    XCTAssertEqual(value as? String, "ErrorUnknown")
  }

  // MARK: read

  func testReadMissingItemReturnsNil() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecItemNotFound, nil)
    XCTAssertNil(invoke(impl, "read", promptArgs()))
  }

  func testReadReturnsDecodedStringAndBuildsModernQuery() {
    let impl = makeImpl()
    initStore(impl, "accounts")
    let payload = "hunter2 \u{1F511}"
    keychain.copyMatchingResult = (errSecSuccess, payload.data(using: .utf8)! as NSData)

    let value = invoke(impl, "read", promptArgs("accounts", access: "Unlock accounts"))

    XCTAssertEqual(value as? String, payload)
    XCTAssertEqual(keychain.copyMatchingQueries.count, 1)
    let query = keychain.copyMatchingQueries[0]
    // Exact query shape: no deprecated kSecUseOperationPrompt, no access
    // control object in search queries.
    XCTAssertEqual(
      Set(query.keys),
      keys([
        kSecClass, kSecAttrService, kSecAttrAccount, kSecMatchLimit,
        kSecReturnData, kSecUseDataProtectionKeychain, kSecUseAuthenticationContext,
      ]))
    XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
    XCTAssertEqual(query[kSecAttrService as String] as? String, "flutter_biometric_vault")
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "accounts")
    XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
    XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)

    // The prompt comes from LAContext.localizedReason on the attached
    // context instead of the deprecated kSecUseOperationPrompt.
    let context = query[kSecUseAuthenticationContext as String] as? FakeLAContext
    XCTAssertNotNil(context)
    XCTAssertTrue(context === contexts.first)
    XCTAssertEqual(context?.localizedReason, "Unlock accounts")
  }

  func testReadWithoutAuthenticationRequiredOmitsAuthKeys() {
    let impl = makeImpl()
    initStore(impl, options: ["authenticationRequired": false])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())

    let query = keychain.copyMatchingQueries[0]
    XCTAssertEqual(
      Set(query.keys),
      keys([kSecClass, kSecAttrService, kSecAttrAccount, kSecMatchLimit, kSecReturnData]))
    XCTAssertEqual(contextFactoryCallCount, 0)
  }

  func testReadUserCanceledMapsToAuthErrorUserCanceled() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecUserCanceled, nil)
    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:UserCanceled")
  }

  func testReadAuthFailedMapsToAuthErrorAuthenticationFailed() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecAuthFailed, nil)
    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:AuthenticationFailed")
  }

  func testReadInteractionNotAllowedMapsToAuthErrorCanceled() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecInteractionNotAllowed, nil)
    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:Canceled")
  }

  func testReadOtherFailureMapsToSecurityError() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecIO, nil)
    assertError(invoke(impl, "read", promptArgs()), code: "SecurityError")
  }

  func testReadWithUndecodableItemReturnsRetrieveError() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecSuccess, Data([0xFF, 0xFE, 0xFD]) as NSData)
    assertError(invoke(impl, "read", promptArgs()), code: "RetrieveError")
  }

  // MARK: write

  func testWriteAddsItemWithBiometryCurrentSetAccessControl() {
    let impl = makeImpl()
    initStore(impl, "vault")

    let value = invoke(
      impl, "write",
      promptArgs("vault", save: "Unlock to save", extra: ["content": "s3cret"]))

    XCTAssertNil(value)
    XCTAssertEqual(keychain.addedAttributes.count, 1)
    XCTAssertEqual(recordedAccessControlFlags, [.biometryCurrentSet])
    let attributes = keychain.addedAttributes[0]
    XCTAssertEqual(
      Set(attributes.keys),
      keys([
        kSecClass, kSecAttrService, kSecAttrAccount, kSecValueData,
        kSecAttrAccessControl, kSecUseDataProtectionKeychain,
        kSecUseAuthenticationContext,
      ]))
    XCTAssertEqual(attributes[kSecAttrService as String] as? String, "flutter_biometric_vault")
    XCTAssertEqual(attributes[kSecAttrAccount as String] as? String, "vault")
    XCTAssertEqual(attributes[kSecValueData as String] as? Data, "s3cret".data(using: .utf8))
    XCTAssertEqual(attributes[kSecUseDataProtectionKeychain as String] as? Bool, true)
    let context = attributes[kSecUseAuthenticationContext as String] as? FakeLAContext
    XCTAssertEqual(context?.localizedReason, "Unlock to save")
  }

  func testWriteWithoutBiometricOnlyUsesUserPresence() {
    let impl = makeImpl()
    initStore(impl, options: ["darwinBiometricOnly": false])
    invoke(impl, "write", promptArgs(extra: ["content": "s3cret"]))
    XCTAssertEqual(recordedAccessControlFlags, [.userPresence])
  }

  func testWriteWithoutAuthenticationRequiredStoresPlainAccessibleItem() {
    let impl = makeImpl()
    initStore(impl, options: ["authenticationRequired": false])

    let value = invoke(impl, "write", promptArgs(extra: ["content": "plain"]))

    XCTAssertNil(value)
    XCTAssertTrue(recordedAccessControlFlags.isEmpty)
    let attributes = keychain.addedAttributes[0]
    XCTAssertEqual(
      Set(attributes.keys),
      keys([kSecClass, kSecAttrService, kSecAttrAccount, kSecValueData, kSecAttrAccessible]))
    XCTAssertEqual(
      attributes[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleWhenUnlocked as String)
  }

  func testWriteUpdatesExistingItem() {
    let impl = makeImpl()
    initStore(impl)
    keychain.addResult = errSecDuplicateItem

    let value = invoke(impl, "write", promptArgs(extra: ["content": "updated"]))

    XCTAssertNil(value)
    XCTAssertEqual(keychain.updateCalls.count, 1)
    let (query, attributes) = keychain.updateCalls[0]
    XCTAssertEqual(attributes[kSecValueData as String] as? Data, "updated".data(using: .utf8))
    XCTAssertEqual(attributes.count, 1, "update must only touch the value")
    XCTAssertEqual(
      Set(query.keys),
      keys([
        kSecClass, kSecAttrService, kSecAttrAccount,
        kSecUseDataProtectionKeychain, kSecUseAuthenticationContext,
      ]))
  }

  func testWriteUserCanceledMapsToAuthErrorUserCanceled() {
    let impl = makeImpl()
    initStore(impl)
    keychain.addResult = errSecUserCanceled
    assertError(invoke(impl, "write", promptArgs(extra: ["content": "x"])),
                code: "AuthError:UserCanceled")
  }

  func testWriteFailureMapsToSecurityError() {
    let impl = makeImpl()
    initStore(impl)
    keychain.addResult = errSecNotAvailable
    assertError(invoke(impl, "write", promptArgs(extra: ["content": "x"])),
                code: "SecurityError")
  }

  func testFailedAccessControlCreationReturnsErrorWithoutTouchingKeychain() {
    let impl = makeImpl(accessControlFactory: { _ in nil })
    initStore(impl)
    let value = invoke(impl, "write", promptArgs(extra: ["content": "x"]))
    assertError(value, code: "SecurityError")
    XCTAssertTrue(keychain.addedAttributes.isEmpty)
  }

  // MARK: silent writes

  func testSilentWriteReplacesItemWithoutAuthContext() {
    let impl = makeImpl()
    initStore(impl, "vault", options: ["silentWrites": true])

    let value = invoke(
      impl, "write",
      promptArgs("vault", save: "Unlock to save", extra: ["content": "s3cret"]))

    XCTAssertNil(value)
    // Silent writes replace the item: delete first, then add. The update
    // path (which prompts on protected items) must never be used.
    XCTAssertEqual(keychain.deleteQueries.count, 1)
    XCTAssertEqual(keychain.addedAttributes.count, 1)
    XCTAssertTrue(keychain.updateCalls.isEmpty)

    let attributes = keychain.addedAttributes[0]
    XCTAssertEqual(
      Set(attributes.keys),
      keys([
        kSecClass, kSecAttrService, kSecAttrAccount, kSecValueData,
        kSecAttrAccessControl, kSecUseDataProtectionKeychain,
      ]),
      "silent writes must not attach an authentication context")
    XCTAssertEqual(recordedAccessControlFlags, [.biometryCurrentSet],
                   "reads stay gated: the access control still applies")
    XCTAssertEqual(contextFactoryCallCount, 0,
                   "no LAContext may be created for a silent write")
  }

  func testSilentWriteFailureStillMapsErrors() {
    let impl = makeImpl()
    initStore(impl, options: ["silentWrites": true])
    keychain.addResult = errSecNotAvailable
    assertError(invoke(impl, "write", promptArgs(extra: ["content": "x"])),
                code: "SecurityError")
  }

  func testSilentWritesLeaveReadsGated() {
    let impl = makeImpl()
    initStore(impl, options: ["silentWrites": true])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())

    let query = keychain.copyMatchingQueries[0]
    XCTAssertNotNil(query[kSecUseAuthenticationContext as String],
                    "reads on a silent-writes store still authenticate")
  }

  func testNonSilentWriteStillUsesUpdatePath() {
    let impl = makeImpl()
    initStore(impl)
    keychain.addResult = errSecDuplicateItem

    invoke(impl, "write", promptArgs(extra: ["content": "updated"]))

    XCTAssertEqual(keychain.updateCalls.count, 1)
    XCTAssertTrue(keychain.deleteQueries.isEmpty)
  }

  // MARK: biometryType

  private func biometryTypeResult(_ type: LABiometryType) -> Any? {
    let context = FakeLAContext()
    context.biometryTypeOverride = type
    let impl = makeImpl(nextContext: { context })
    return invoke(impl, "biometryType", nil)
  }

  func testBiometryTypeMapsFaceId() {
    XCTAssertEqual(biometryTypeResult(.faceID) as? String, "FaceId")
  }

  func testBiometryTypeMapsTouchId() {
    XCTAssertEqual(biometryTypeResult(.touchID) as? String, "TouchId")
  }

  func testBiometryTypeMapsNone() {
    XCTAssertEqual(biometryTypeResult(.none) as? String, "None")
  }

  func testBiometryTypeProbesPolicyFirst() {
    // biometryType is only populated after canEvaluatePolicy, so the
    // implementation must probe before reading it.
    let context = FakeLAContext()
    context.biometryTypeOverride = .faceID
    let impl = makeImpl(nextContext: { context })
    _ = invoke(impl, "biometryType", nil)
    XCTAssertEqual(context.evaluatedPolicies, [.deviceOwnerAuthenticationWithBiometrics])
  }

  // MARK: authenticate

  func testAuthenticateSuccessReturnsTrueAndUsesDeviceOwnerPolicy() {
    let context = FakeLAContext()
    context.evaluateResult = true
    let impl = makeImpl(nextContext: { context })

    let value = invoke(
      impl, "authenticate",
      ["biometricOnly": false, "iosPromptInfo": ["accessTitle": "Unlock the app"]])

    XCTAssertEqual(value as? Bool, true)
    XCTAssertEqual(context.evaluateCalls.count, 1)
    XCTAssertEqual(context.evaluateCalls[0].policy, .deviceOwnerAuthentication)
    XCTAssertEqual(context.evaluateCalls[0].reason, "Unlock the app")
  }

  func testAuthenticateBiometricOnlyUsesBiometricsPolicyAndHidesFallback() {
    let context = FakeLAContext()
    context.evaluateResult = true
    let impl = makeImpl(nextContext: { context })

    invoke(impl, "authenticate",
           ["biometricOnly": true, "iosPromptInfo": ["accessTitle": "Verify"]])

    XCTAssertEqual(context.evaluateCalls[0].policy, .deviceOwnerAuthenticationWithBiometrics)
    XCTAssertEqual(context.localizedFallbackTitle, "",
                   "biometric-only must hide the passcode fallback button")
  }

  func testAuthenticateUserCancelMapsToAuthErrorUserCanceled() {
    let context = FakeLAContext()
    context.evaluateResult = false
    context.evaluateError = laError(LAError.userCancel.rawValue)
    let impl = makeImpl(nextContext: { context })
    assertError(
      invoke(impl, "authenticate", ["iosPromptInfo": ["accessTitle": "Verify"]]),
      code: "AuthError:UserCanceled")
  }

  func testAuthenticateLockoutMapsToAuthErrorLockedOut() {
    let context = FakeLAContext()
    context.evaluateResult = false
    context.evaluateError = laError(LAError.biometryLockout.rawValue)
    let impl = makeImpl(nextContext: { context })
    assertError(
      invoke(impl, "authenticate", ["iosPromptInfo": ["accessTitle": "Verify"]]),
      code: "AuthError:LockedOut")
  }

  func testAuthenticateSystemCancelMapsToAuthErrorCanceled() {
    let context = FakeLAContext()
    context.evaluateResult = false
    context.evaluateError = laError(LAError.systemCancel.rawValue)
    let impl = makeImpl(nextContext: { context })
    assertError(
      invoke(impl, "authenticate", ["iosPromptInfo": ["accessTitle": "Verify"]]),
      code: "AuthError:Canceled")
  }

  func testAuthenticateNotEnrolledMapsToAuthErrorNoBiometricEnrolled() {
    let context = FakeLAContext()
    context.evaluateResult = false
    context.evaluateError = laError(LAError.biometryNotEnrolled.rawValue)
    let impl = makeImpl(nextContext: { context })
    assertError(
      invoke(impl, "authenticate", ["iosPromptInfo": ["accessTitle": "Verify"]]),
      code: "AuthError:NoBiometricEnrolled")
  }

  // MARK: errSecAuthFailed lockout attribution

  /// Context whose canEvaluatePolicy fails with the given LAError code, as
  /// handed to the post-flight lockout probe.
  private func evaluationFailingContext(_ errorCode: Int) -> FakeLAContext {
    let context = FakeLAContext()
    context.canEvaluateResult = false
    context.canEvaluateError = laError(errorCode)
    return context
  }

  /// makeImpl variant whose context factory hands out `sequence` in order,
  /// then falls back to fresh default contexts.
  private func makeImpl(handingOut sequence: [FakeLAContext]) -> BiometricVaultImpl {
    var pending = sequence
    return makeImpl(nextContext: {
      pending.isEmpty ? FakeLAContext() : pending.removeFirst()
    })
  }

  func testReadAuthFailedWhileLockedOutMapsToAuthErrorLockedOut() {
    let probe = evaluationFailingContext(LAError.biometryLockout.rawValue)
    let impl = makeImpl(handingOut: [FakeLAContext(), probe])
    initStore(impl)
    keychain.copyMatchingResult = (errSecAuthFailed, nil)

    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:LockedOut")

    XCTAssertEqual(contextFactoryCallCount, 2, "operation context plus one probe context")
    XCTAssertEqual(probe.evaluatedPolicies, [.deviceOwnerAuthenticationWithBiometrics])
    XCTAssertEqual(contextFactoryThreadWasMain, [false, false],
                   "the lockout probe must run on the work queue, never the main thread")
  }

  func testWriteAuthFailedWhileLockedOutMapsToAuthErrorLockedOut() {
    let probe = evaluationFailingContext(LAError.biometryLockout.rawValue)
    let impl = makeImpl(handingOut: [FakeLAContext(), probe])
    initStore(impl)
    keychain.addResult = errSecAuthFailed

    assertError(invoke(impl, "write", promptArgs(extra: ["content": "x"])),
                code: "AuthError:LockedOut")

    XCTAssertEqual(contextFactoryCallCount, 2, "operation context plus one probe context")
    XCTAssertEqual(probe.evaluatedPolicies, [.deviceOwnerAuthenticationWithBiometrics])
  }

  func testReadAuthFailedWithNonLockoutProbeStaysAuthenticationFailed() {
    let probe = evaluationFailingContext(LAError.biometryNotAvailable.rawValue)
    let impl = makeImpl(handingOut: [FakeLAContext(), probe])
    initStore(impl)
    keychain.copyMatchingResult = (errSecAuthFailed, nil)

    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:AuthenticationFailed")

    XCTAssertEqual(probe.evaluatedPolicies, [.deviceOwnerAuthenticationWithBiometrics])
  }

  func testAuthFailedOnUnauthenticatedStoreDoesNotProbeLockout() {
    let impl = makeImpl()
    initStore(impl, options: ["authenticationRequired": false])
    keychain.copyMatchingResult = (errSecAuthFailed, nil)

    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:AuthenticationFailed")

    XCTAssertEqual(contextFactoryCallCount, 0,
                   "unauthenticated stores must never trigger a lockout probe")
  }

  func testLockoutProbeResultIsNotCachedAcrossOperations() {
    let lockedOutProbe = evaluationFailingContext(LAError.biometryLockout.rawValue)
    let impl = makeImpl(
      handingOut: [FakeLAContext(), lockedOutProbe, FakeLAContext(), FakeLAContext()])
    initStore(impl)
    keychain.copyMatchingResult = (errSecAuthFailed, nil)

    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:LockedOut")
    assertError(invoke(impl, "read", promptArgs()), code: "AuthError:AuthenticationFailed")

    XCTAssertEqual(contextFactoryCallCount, 4, "every errSecAuthFailed must probe afresh")
  }

  // MARK: delete

  func testDeleteReturnsTrueOnSuccessAndBuildsPlainQuery() {
    let impl = makeImpl()
    initStore(impl, "vault")
    keychain.deleteResult = errSecSuccess

    XCTAssertEqual(invoke(impl, "delete", promptArgs("vault")) as? Bool, true)

    let query = keychain.deleteQueries[0]
    XCTAssertEqual(
      Set(query.keys),
      keys([kSecClass, kSecAttrService, kSecAttrAccount, kSecUseDataProtectionKeychain]))
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "vault")
  }

  func testDeleteMissingItemStillReturnsTrue() {
    let impl = makeImpl()
    initStore(impl)
    keychain.deleteResult = errSecItemNotFound
    XCTAssertEqual(invoke(impl, "delete", promptArgs()) as? Bool, true)
  }

  func testDeleteFailureMapsToSecurityError() {
    let impl = makeImpl()
    initStore(impl)
    keychain.deleteResult = errSecIO
    assertError(invoke(impl, "delete", promptArgs()), code: "SecurityError")
  }

  // MARK: LAContext configuration and reuse

  func testAllowableReuseDurationIsClampedToSystemMaximum() {
    let impl = makeImpl()
    initStore(
      impl,
      options: ["darwinTouchIDAuthenticationAllowableReuseDurationSeconds": 100_000])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())

    XCTAssertEqual(
      contexts.first?.touchIDAuthenticationAllowableReuseDuration,
      LATouchIDAuthenticationMaximumAllowableReuseDuration)
  }

  func testAllowableReuseDurationIsAppliedWhenWithinLimit() {
    let impl = makeImpl()
    initStore(
      impl, options: ["darwinTouchIDAuthenticationAllowableReuseDurationSeconds": 42])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())

    XCTAssertEqual(contexts.first?.touchIDAuthenticationAllowableReuseDuration, 42)
  }

  func testFreshContextPerOperationWithoutForceReuse() {
    let impl = makeImpl()
    initStore(impl)
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())
    invoke(impl, "read", promptArgs())

    XCTAssertEqual(contextFactoryCallCount, 2)
  }

  func testForceReuseContextDurationReusesContextUntilExpiry() {
    let impl = makeImpl()
    initStore(
      impl,
      options: ["darwinTouchIDAuthenticationForceReuseContextDurationSeconds": 30])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs())
    currentDate = currentDate.addingTimeInterval(10)
    invoke(impl, "read", promptArgs())
    XCTAssertEqual(contextFactoryCallCount, 1, "context must be reused within the window")

    currentDate = currentDate.addingTimeInterval(31)
    invoke(impl, "read", promptArgs())
    XCTAssertEqual(contextFactoryCallCount, 2, "expired context must be replaced")
  }

  func testReusedContextGetsFreshLocalizedReasonPerOperation() {
    let impl = makeImpl()
    initStore(
      impl,
      options: ["darwinTouchIDAuthenticationForceReuseContextDurationSeconds": 60])
    keychain.copyMatchingResult = (errSecItemNotFound, nil)

    invoke(impl, "read", promptArgs(access: "First reason"))
    invoke(impl, "write", promptArgs(save: "Second reason", extra: ["content": "x"]))

    XCTAssertEqual(contextFactoryCallCount, 1)
    XCTAssertEqual(contexts.first?.localizedReason, "Second reason")
  }

  // MARK: Real keychain round trip

  /// Uses the real SystemKeychain (no fakes) through the unauthenticated
  /// path, proving the query shapes are accepted by the Security framework.
  func testEndToEndRoundTripAgainstRealKeychain() {
    let impl = BiometricVaultImpl(
      storageError: { code, message, details in
        TestPluginError(code: code, message: message, details: details)
      },
      storageMethodNotImplemented: notImplemented
    )
    let store = "e2e_\(UUID().uuidString)"
    initStore(impl, store, options: ["authenticationRequired": false])
    defer { invoke(impl, "delete", promptArgs(store)) }

    XCTAssertNil(invoke(impl, "read", promptArgs(store)), "store must start empty")
    XCTAssertNil(invoke(impl, "write", promptArgs(store, extra: ["content": "first"])))
    XCTAssertEqual(invoke(impl, "read", promptArgs(store)) as? String, "first")
    XCTAssertNil(invoke(impl, "write", promptArgs(store, extra: ["content": "second"])),
                 "overwriting must go through the duplicate-item update path")
    XCTAssertEqual(invoke(impl, "read", promptArgs(store)) as? String, "second")
    XCTAssertEqual(invoke(impl, "delete", promptArgs(store)) as? Bool, true)
    XCTAssertNil(invoke(impl, "read", promptArgs(store)), "item must be gone after delete")
  }

  // MARK: Threading

  func testKeychainWorkRunsOffMainThreadAndResultsArriveOnMainThread() {
    let offMainThread = expectation(description: "keychain work off main thread")
    let probe = ThreadProbeKeychain { isMain in
      XCTAssertFalse(isMain, "SecItem calls must not run on the main thread")
      offMainThread.fulfill()
    }
    let impl = makeImpl(keychain: probe)
    initStore(impl)

    let resultArrived = expectation(description: "read result")
    var resultThreadWasMain: Bool?
    impl.handle(StorageMethodCall(method: "read", arguments: promptArgs())) { _ in
      resultThreadWasMain = Thread.isMainThread
      resultArrived.fulfill()
    }
    wait(for: [offMainThread, resultArrived], timeout: 5)
    XCTAssertEqual(resultThreadWasMain, true, "results must be delivered on the main thread")
  }
}
