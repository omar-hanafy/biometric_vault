import FlutterMacOS
import Cocoa

public class BiometricVaultMacOSPlugin: NSObject, FlutterPlugin {
  
  private let impl = BiometricVaultImpl(storageError: { (code, message, details) -> Any in
    FlutterError(code: code, message: message, details: details)
  }, storageMethodNotImplemented: FlutterMethodNotImplemented)
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "biometric_vault", binaryMessenger: registrar.messenger)
    let instance = BiometricVaultMacOSPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    impl.handle(StorageMethodCall(method: call.method, arguments: call.arguments), result: result)
  }

}
