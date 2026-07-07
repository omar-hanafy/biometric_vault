// Shared implementation for iOS and macOS.
// This file lives in macos/Classes and is symlinked into ios/Classes,
// so both platforms always compile the exact same code.
//
// Keychain access follows Apple's current guidance:
// https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id
// - Prompts are configured through LAContext.localizedReason instead of the
//   deprecated kSecUseOperationPrompt.
// - Items requiring authentication use SecAccessControl with
//   kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly.
// - Keychain calls run off the main thread because they can block on user
//   interaction; results are always delivered back on the main thread.

import Foundation
import LocalAuthentication
import Security
import os.log

typealias StorageCallback = (Any?) -> Void
typealias StorageError = (String, String?, Any?) -> Any

private let logger = OSLog(subsystem: "biometric_vault", category: "plugin")

struct StorageMethodCall {
  let method: String
  let arguments: Any?
}

/// Thin seam over the `SecItem*` API so the keychain can be faked in tests.
protocol KeychainClient {
  func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: AnyObject?)
  func add(_ attributes: [String: Any]) -> OSStatus
  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychain: KeychainClient {
  func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: AnyObject?) {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (status, item)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

struct InitOptions {
  init(params: [String: Any]) {
    darwinTouchIDAuthenticationAllowableReuseDuration =
      params["darwinTouchIDAuthenticationAllowableReuseDurationSeconds"] as? Int
    darwinTouchIDAuthenticationForceReuseContextDuration =
      params["darwinTouchIDAuthenticationForceReuseContextDurationSeconds"] as? Int
    authenticationRequired = params["authenticationRequired"] as? Bool ?? true
    darwinBiometricOnly = params["darwinBiometricOnly"] as? Bool ?? true
    silentWrites = params["silentWrites"] as? Bool ?? false
  }

  let darwinTouchIDAuthenticationAllowableReuseDuration: Int?
  let darwinTouchIDAuthenticationForceReuseContextDuration: Int?
  let authenticationRequired: Bool
  let darwinBiometricOnly: Bool

  /// When true, writes replace the keychain item (delete + add) without any
  /// authentication context, so they never prompt; reads stay gated through
  /// the item's access control.
  let silentWrites: Bool
}

struct IOSPromptInfo {
  init(params: [String: Any]) {
    saveTitle = params["saveTitle"] as? String
    accessTitle = params["accessTitle"] as? String
  }

  let saveTitle: String?
  let accessTitle: String?
}

/// Shared dependencies handed to every storage file.
struct StorageEnvironment {
  let keychain: KeychainClient
  let contextFactory: () -> LAContext
  let accessControlFactory: (SecAccessControlCreateFlags) -> SecAccessControl?
  let now: () -> Date
  let workQueue: DispatchQueue
  let storageError: StorageError
}

/// Results must reach Flutter on the main (platform) thread.
private func completeOnMain(_ value: Any?, _ result: @escaping StorageCallback) {
  DispatchQueue.main.async {
    result(value)
  }
}

private func defaultAccessControl(_ flags: SecAccessControlCreateFlags) -> SecAccessControl? {
  var error: Unmanaged<CFError>?
  guard let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    flags,
    &error
  ) else {
    os_log(.error, log: logger, "Unable to create access control: %{public}@",
           String(describing: error?.takeRetainedValue()))
    return nil
  }
  return access
}

class BiometricVaultImpl {

  init(
    storageError: @escaping StorageError,
    storageMethodNotImplemented: Any,
    keychain: KeychainClient = SystemKeychain(),
    contextFactory: @escaping () -> LAContext = { LAContext() },
    accessControlFactory: ((SecAccessControlCreateFlags) -> SecAccessControl?)? = nil,
    now: @escaping () -> Date = { Date() }
  ) {
    self.storageError = storageError
    self.storageMethodNotImplemented = storageMethodNotImplemented
    self.environment = StorageEnvironment(
      keychain: keychain,
      contextFactory: contextFactory,
      accessControlFactory: accessControlFactory ?? defaultAccessControl(_:),
      now: now,
      workQueue: DispatchQueue(label: "biometric_vault.keychain", qos: .userInitiated),
      storageError: storageError
    )
  }

  private let storageError: StorageError
  private let storageMethodNotImplemented: Any
  private let environment: StorageEnvironment
  private var stores: [String: BiometricVaultFile] = [:]

  public func handle(_ call: StorageMethodCall, result: @escaping StorageCallback) {
    let args = call.arguments as? [String: Any] ?? [:]

    func fail(_ code: String, _ message: String) {
      completeOnMain(storageError(code, message, nil), result)
    }

    func requiredArg<T>(_ name: String) -> T? {
      guard let value = args[name] else {
        fail("InvalidArguments", "Missing argument '\(name)' for method '\(call.method)'.")
        return nil
      }
      guard let typed = value as? T else {
        fail("InvalidArguments",
             "Invalid argument for '\(name)': expected \(T.self), got \(type(of: value)).")
        return nil
      }
      return typed
    }

    func requiredStorage(_ name: String) -> BiometricVaultFile? {
      guard let file = stores[name] else {
        fail("NoSuchStorage", "Storage '\(name)' was not initialized.")
        return nil
      }
      return file
    }

    switch call.method {
    case "canAuthenticate":
      guard let optionsParams: [String: Any] = requiredArg("options") else { return }
      canAuthenticate(options: InitOptions(params: optionsParams), result: result)

    case "biometryType":
      biometryType(result: result)

    case "authenticate":
      let biometricOnly = args["biometricOnly"] as? Bool ?? false
      let promptParams = args["iosPromptInfo"] as? [String: Any] ?? [:]
      authenticate(
        biometricOnly: biometricOnly,
        reason: IOSPromptInfo(params: promptParams).accessTitle ?? "Authenticate",
        result: result)

    case "init":
      guard let name: String = requiredArg("name"),
            let optionsParams: [String: Any] = requiredArg("options") else { return }
      let forceInit = args["forceInit"] as? Bool ?? false
      guard stores[name] == nil else {
        if forceInit {
          fail("AlreadyInitialized",
               "A storage file with the name '\(name)' was already initialized.")
        } else {
          completeOnMain(false, result)
        }
        return
      }
      stores[name] = BiometricVaultFile(
        name: name,
        options: InitOptions(params: optionsParams),
        environment: environment
      )
      completeOnMain(true, result)

    case "dispose":
      guard let name: String = requiredArg("name") else { return }
      guard stores.removeValue(forKey: name) != nil else {
        fail("NoSuchStorage", "Tried to dispose non-existing storage '\(name)'.")
        return
      }
      completeOnMain(true, result)

    case "read":
      guard let name: String = requiredArg("name"),
            let promptParams: [String: Any] = requiredArg("iosPromptInfo"),
            let file = requiredStorage(name) else { return }
      file.read(IOSPromptInfo(params: promptParams), result)

    case "write":
      guard let name: String = requiredArg("name"),
            let content: String = requiredArg("content"),
            let promptParams: [String: Any] = requiredArg("iosPromptInfo"),
            let file = requiredStorage(name) else { return }
      file.write(content, IOSPromptInfo(params: promptParams), result)

    case "delete":
      guard let name: String = requiredArg("name"),
            let _: [String: Any] = requiredArg("iosPromptInfo"),
            let file = requiredStorage(name) else { return }
      file.delete(result)

    default:
      completeOnMain(storageMethodNotImplemented, result)
    }
  }

  private func canAuthenticate(options: InitOptions, result: @escaping StorageCallback) {
    let policy: LAPolicy = options.darwinBiometricOnly
      ? .deviceOwnerAuthenticationWithBiometrics
      : .deviceOwnerAuthentication
    let context = environment.contextFactory()
    var error: NSError?
    if context.canEvaluatePolicy(policy, error: &error) {
      completeOnMain("Success", result)
      return
    }
    guard let error else {
      completeOnMain("ErrorUnknown", result)
      return
    }
    os_log(.info, log: logger, "canEvaluatePolicy failed: %{public}@", error)
    completeOnMain(Self.canAuthenticateCode(for: error), result)
  }

  /// Reports the biometry modality as the wire name consumed by the Dart
  /// `BiometryType` mapping. `LAContext.biometryType` is only populated
  /// after a policy evaluation, hence the probing `canEvaluatePolicy` call.
  private func biometryType(result: @escaping StorageCallback) {
    let context = environment.contextFactory()
    var error: NSError?
    _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let name: String
    switch context.biometryType {
    case .faceID:
      name = "FaceId"
    case .touchID:
      name = "TouchId"
    case .none:
      name = "None"
    default:
      if #available(iOS 17.0, macOS 14.0, *), context.biometryType == .opticID {
        name = "OpticId"
      } else {
        name = "Unknown"
      }
    }
    completeOnMain(name, result)
  }

  /// Standalone user authentication without any keychain item, for app-lock
  /// style gates. Replies `true` on success and the same `AuthError:*` codes
  /// as storage operations on failure.
  private func authenticate(
    biometricOnly: Bool, reason: String, result: @escaping StorageCallback
  ) {
    let policy: LAPolicy = biometricOnly
      ? .deviceOwnerAuthenticationWithBiometrics
      : .deviceOwnerAuthentication
    let context = environment.contextFactory()
    if biometricOnly {
      // An empty fallback title hides the passcode button entirely.
      context.localizedFallbackTitle = ""
    }
    let storageError = self.storageError
    context.evaluatePolicy(policy, localizedReason: reason) { success, error in
      if success {
        completeOnMain(true, result)
        return
      }
      let code = Self.authenticateErrorCode(for: error as NSError?)
      let message = (error as NSError?)?.localizedDescription ?? "Authentication failed."
      os_log(.info, log: logger, "authenticate failed: %{public}@ (%{public}@)", code, message)
      completeOnMain(storageError(code, message, nil), result)
    }
  }

  private static func authenticateErrorCode(for error: NSError?) -> String {
    guard let error, error.domain == LAErrorDomain else {
      return "AuthError:Unknown"
    }
    switch LAError(_nsError: error).code {
    case .userCancel, .userFallback:
      // userFallback only fires when the fallback button is visible but no
      // fallback exists (biometric-only); the user opted out either way.
      return "AuthError:UserCanceled"
    case .systemCancel, .appCancel, .notInteractive:
      return "AuthError:Canceled"
    case .authenticationFailed:
      return "AuthError:AuthenticationFailed"
    case .biometryLockout:
      return "AuthError:LockedOut"
    case .biometryNotEnrolled:
      return "AuthError:NoBiometricEnrolled"
    case .biometryNotAvailable:
      return "AuthError:HardwareUnavailable"
    case .passcodeNotSet:
      return "AuthError:PasscodeNotSet"
    default:
      return "AuthError:Unknown"
    }
  }

  private static func canAuthenticateCode(for error: NSError) -> String {
    guard error.domain == LAErrorDomain else {
      return "ErrorUnknown"
    }
    #if os(macOS)
    if #available(macOS 11.2, *) {
      // A Mac can lack paired biometry (no built-in or paired Touch ID) or
      // temporarily lose it (Magic Keyboard disconnected).
      if error.code == LAError.biometryNotPaired.rawValue {
        return "ErrorNoHardware"
      }
      if error.code == LAError.biometryDisconnected.rawValue {
        return "ErrorHwUnavailable"
      }
    }
    #endif
    switch LAError(_nsError: error).code {
    case .biometryNotAvailable:
      return "ErrorHwUnavailable"
    case .biometryLockout:
      // Biometry is enrolled but temporarily locked after too many failed
      // attempts; it becomes available again after passcode authentication.
      return "ErrorLockedOut"
    case .biometryNotEnrolled:
      return "ErrorNoBiometricEnrolled"
    case .passcodeNotSet:
      return "ErrorPasscodeNotSet"
    default:
      return "ErrorUnknown"
    }
  }
}

class BiometricVaultFile {

  init(name: String, options: InitOptions, environment: StorageEnvironment) {
    self.name = name
    self.options = options
    self.env = environment
  }

  private let name: String
  private let options: InitOptions
  private let env: StorageEnvironment
  /// Only accessed on `env.workQueue`.
  private var cachedContext: (context: LAContext, expiresAt: Date)?

  /// Base attributes identifying this store's keychain item. Search queries
  /// deliberately never contain `kSecAttrAccessControl`; access control is an
  /// item creation attribute, not a match criterion.
  private var baseQuery: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "flutter_biometric_vault",
      kSecAttrAccount as String: name,
    ]
    if options.authenticationRequired {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  /// Returns the LAContext for an operation, honoring the configured reuse
  /// durations. Must be called on `env.workQueue`.
  private func authContext(reason: String?) -> LAContext {
    let context: LAContext
    if let cached = cachedContext, cached.expiresAt > env.now() {
      context = cached.context
    } else {
      cachedContext = nil
      context = env.contextFactory()
      if let seconds = options.darwinTouchIDAuthenticationAllowableReuseDuration {
        context.touchIDAuthenticationAllowableReuseDuration = min(
          Double(seconds), LATouchIDAuthenticationMaximumAllowableReuseDuration)
      }
      if let seconds = options.darwinTouchIDAuthenticationForceReuseContextDuration {
        cachedContext = (
          context: context,
          expiresAt: env.now().addingTimeInterval(Double(seconds))
        )
      }
    }
    // The keychain prompt shows LAContext.localizedReason; this replaces the
    // deprecated kSecUseOperationPrompt query attribute.
    if let reason, !reason.isEmpty {
      context.localizedReason = reason
    }
    return context
  }

  func read(_ promptInfo: IOSPromptInfo, _ result: @escaping StorageCallback) {
    env.workQueue.async { [self] in
      var query = baseQuery
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      query[kSecReturnData as String] = true
      if options.authenticationRequired {
        query[kSecUseAuthenticationContext as String] =
          authContext(reason: promptInfo.accessTitle)
      }
      let (status, item) = env.keychain.copyMatching(query)
      guard status != errSecItemNotFound else {
        completeOnMain(nil, result)
        return
      }
      guard status == errSecSuccess else {
        completeError(status, while: "reading data", result)
        return
      }
      guard let data = item as? Data,
            let content = String(data: data, encoding: .utf8) else {
        completeOnMain(
          env.storageError("RetrieveError", "Unexpected data in keychain item.", nil),
          result)
        return
      }
      completeOnMain(content, result)
    }
  }

  func write(_ content: String, _ promptInfo: IOSPromptInfo, _ result: @escaping StorageCallback) {
    env.workQueue.async { [self] in
      guard let value = content.data(using: .utf8) else {
        completeOnMain(
          env.storageError("WriteError", "Unable to encode content to UTF-8.", nil),
          result)
        return
      }

      var context: LAContext?
      var attributes = baseQuery
      if options.authenticationRequired {
        let flags: SecAccessControlCreateFlags =
          options.darwinBiometricOnly ? .biometryCurrentSet : .userPresence
        guard let accessControl = env.accessControlFactory(flags) else {
          completeOnMain(
            env.storageError(
              "SecurityError", "Unable to create access control for '\(name)'.", nil),
            result)
          return
        }
        attributes[kSecAttrAccessControl as String] = accessControl
        if !options.silentWrites {
          let operationContext = authContext(reason: promptInfo.saveTitle)
          attributes[kSecUseAuthenticationContext as String] = operationContext
          context = operationContext
        }
      } else {
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      }
      attributes[kSecValueData as String] = value

      if options.authenticationRequired && options.silentWrites {
        // Silent write: replace the item. SecItemAdd never evaluates the
        // access control (it only applies to future reads), and skipping the
        // update path avoids the prompt SecItemUpdate would trigger on a
        // protected item.
        _ = env.keychain.delete(baseQuery)
        let status = env.keychain.add(attributes)
        guard status == errSecSuccess else {
          completeError(status, while: "writing data", result)
          return
        }
        completeOnMain(nil, result)
        return
      }

      var status = env.keychain.add(attributes)
      if status == errSecDuplicateItem {
        // Updating (instead of delete + add) keeps the existing item's access
        // control and forces user authentication for protected items.
        var query = baseQuery
        if let context {
          query[kSecUseAuthenticationContext as String] = context
        }
        status = env.keychain.update(query, [kSecValueData as String: value])
      }
      guard status == errSecSuccess else {
        completeError(status, while: "writing data", result)
        return
      }
      completeOnMain(nil, result)
    }
  }

  func delete(_ result: @escaping StorageCallback) {
    env.workQueue.async { [self] in
      let status = env.keychain.delete(baseQuery)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        completeError(status, while: "deleting data", result)
        return
      }
      completeOnMain(true, result)
    }
  }

  private func completeError(
    _ status: OSStatus, while action: String, _ result: @escaping StorageCallback
  ) {
    let description = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
    let code: String
    switch status {
    case errSecUserCanceled:
      code = "AuthError:UserCanceled"
    case errSecAuthFailed:
      // The keychain reports errSecAuthFailed for a failed biometric match
      // and for biometry lockout alike; a post-flight probe tells them apart.
      code = isBiometryLockedOut()
        ? "AuthError:LockedOut"
        : "AuthError:AuthenticationFailed"
    case errSecInteractionNotAllowed:
      code = "AuthError:Canceled"
    default:
      code = "SecurityError"
    }
    os_log(.error, log: logger, "Error while %{public}@: %d %{public}@",
           action, status, description)
    completeOnMain(
      env.storageError(code, "Error while \(action): \(status): \(description)", nil),
      result)
  }

  /// Disambiguates `errSecAuthFailed` after a keychain operation on an
  /// auth-required store. A fresh probe context (never the operation context,
  /// whose state the failed operation may have poisoned) asks
  /// LocalAuthentication whether biometry is currently locked out. The result
  /// is intentionally not cached because lockout ends with the next passcode
  /// authentication. Must be called on `env.workQueue`.
  private func isBiometryLockedOut() -> Bool {
    guard options.authenticationRequired else {
      return false
    }
    let probe = env.contextFactory()
    var error: NSError?
    if probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      return false
    }
    guard let error, error.domain == LAErrorDomain else {
      return false
    }
    return LAError(_nsError: error).code == .biometryLockout
  }
}
