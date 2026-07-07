package io.github.omarhanafy.biometric_vault

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import kotlin.time.Duration.Companion.seconds

/**
 * Android implementation of the `biometric_vault` plugin.
 *
 * Values are encrypted with AES/GCM keys kept in the Android Keystore and,
 * when authentication is required, gated behind the system biometric prompt.
 *
 * Threading model: method calls arrive on the platform main thread, all
 * keystore and file work runs on a single background worker, prompts are
 * shown on the main thread and every reply is delivered exactly once on the
 * main thread through [MainThreadResult].
 */
class BiometricVaultPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "biometric_vault"
        private const val PARAM_NAME = "name"
        private const val PARAM_WRITE_CONTENT = "content"
        private const val PARAM_ANDROID_PROMPT_INFO = "androidPromptInfo"
    }

    private lateinit var applicationContext: Context
    private lateinit var authenticator: BiometricAuthenticator
    private var channel: MethodChannel? = null
    private var workerExecutor: ExecutorService? = null
    private var attachedActivity: FragmentActivity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val storageFiles = mutableMapOf<String, BiometricVaultFile>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        authenticator = BiometricAuthenticator(binding.applicationContext)
        workerExecutor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "BiometricVaultWorker")
        }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        workerExecutor?.shutdown()
        workerExecutor = null
        storageFiles.clear()
    }

    override fun onMethodCall(call: MethodCall, rawResult: Result) {
        StorageLog.d { "onMethodCall(${call.method})" }
        val result = MainThreadResult(rawResult)
        try {
            when (call.method) {
                "canAuthenticate" ->
                    result.success(authenticator.canAuthenticate(parseInitOptions(call)).name)

                "init" -> initStorage(call, result)

                "dispose" -> disposeStorage(call, result)

                "read" -> withStorage(call, result) { storage ->
                    executeWithAuthentication(
                        storage,
                        CipherMode.Decrypt,
                        promptInfoProvider(call),
                        result,
                    ) { cipher ->
                        result.success(storage.readFile(cipher))
                    }
                }

                "write" -> withStorage(call, result) { storage ->
                    val content = requiredArgument<String>(call, PARAM_WRITE_CONTENT)
                    executeWithAuthentication(
                        storage,
                        CipherMode.Encrypt,
                        promptInfoProvider(call),
                        result,
                    ) { cipher ->
                        storage.writeFile(cipher, content)
                        result.success(true)
                    }
                }

                "delete" -> withStorage(call, result) { storage ->
                    runOnWorker(result) {
                        if (storage.exists()) {
                            result.success(storage.deleteFile())
                        } else {
                            result.success(false)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            sendError(result, e, call.method)
        }
    }

    private fun initStorage(call: MethodCall, result: MainThreadResult) {
        val name = requiredArgument<String>(call, PARAM_NAME)
        if (storageFiles.containsKey(name)) {
            if (call.argument<Boolean>("forceInit") == true) {
                throw MethodCallException(
                    "AlreadyInitialized",
                    "A storage file with the name '$name' was already initialized.",
                )
            }
            result.success(false)
            return
        }
        storageFiles[name] = BiometricVaultFile(applicationContext, name, parseInitOptions(call))
        result.success(true)
    }

    private fun disposeStorage(call: MethodCall, result: MainThreadResult) {
        val name = requiredArgument<String>(call, PARAM_NAME)
        val storage = storageFiles.remove(name)
            ?: throw MethodCallException("NoSuchStorage", "Tried to dispose non existing storage.", null)
        storage.dispose()
        result.success(true)
    }

    /**
     * Runs [task] on the worker after the authentication the storage options
     * demand succeeded, following the key authorization patterns from
     * https://developer.android.com/identity/sign-in/biometric-auth
     */
    @MainThread
    private fun executeWithAuthentication(
        storage: BiometricVaultFile,
        mode: CipherMode,
        promptInfo: () -> AndroidPromptInfo,
        result: MainThreadResult,
        @WorkerThread task: (cipher: Cipher?) -> Unit,
    ) {
        if (!storage.options.authenticationRequired) {
            runOnWorker(result) { task(null) }
            return
        }

        if (storage.options.silentWrites && mode == CipherMode.Encrypt) {
            // Silent-writes storage encrypts with the public key; no
            // authentication (and no prompt) is ever needed for writes.
            runOnWorker(result) { task(null) }
            return
        }

        if (storage.options.androidAuthenticationValidityDuration != null) {
            // Time-bound key: it must not be bound to a CryptoObject. Try the
            // operation first and only show the prompt when the keystore
            // rejects the key because the validity window expired.
            runOnWorker(result) {
                try {
                    task(null)
                } catch (e: Throwable) {
                    if (!isUserNotAuthenticated(e)) throw e
                    StorageLog.d { "User requires (re)authentication, showing prompt." }
                    mainHandler.post {
                        showPrompt(storage, null, promptInfo, result) {
                            runOnWorker(result) { task(null) }
                        }
                    }
                }
            }
            return
        }

        // Auth-per-use key: initialize the cipher up front and authorize
        // exactly this cipher through the prompt's CryptoObject.
        runOnWorker(result) {
            val cipher = when (mode) {
                CipherMode.Encrypt -> storage.cipherForEncrypt()
                CipherMode.Decrypt -> storage.cipherForDecrypt()
            }
            if (cipher == null) {
                // Nothing stored yet, so there is nothing to authorize or decrypt.
                task(null)
                return@runOnWorker
            }
            mainHandler.post {
                showPrompt(storage, cipher, promptInfo, result) { authenticatedCipher ->
                    runOnWorker(result) { task(authenticatedCipher ?: cipher) }
                }
            }
        }
    }

    @MainThread
    private fun showPrompt(
        storage: BiometricVaultFile,
        cipher: Cipher?,
        promptInfo: () -> AndroidPromptInfo,
        result: MainThreadResult,
        onSuccess: (cipher: Cipher?) -> Unit,
    ) {
        try {
            val activity = attachedActivity
            if (activity == null) {
                StorageLog.e("Cannot show a biometric prompt without a foreground FragmentActivity.")
                result.error(
                    "AuthError:${AuthenticationError.FailedToStart}",
                    "Plugin is not attached to a FragmentActivity. " +
                        "Use FlutterFragmentActivity in your app.",
                    null,
                )
                return
            }
            authenticator.authenticate(
                activity,
                cipher,
                promptInfo(),
                storage.options,
                onSuccess,
            ) { errorInfo ->
                StorageLog.e("AuthError: $errorInfo")
                result.error(
                    "AuthError:${errorInfo.error}",
                    errorInfo.message.toString(),
                    errorInfo.errorDetails,
                )
            }
        } catch (e: Throwable) {
            sendError(result, e)
        }
    }

    private fun runOnWorker(result: MainThreadResult, @WorkerThread body: () -> Unit) {
        val executor = workerExecutor
        if (executor == null) {
            result.error("Unexpected Error", "Plugin is not attached to a Flutter engine.", null)
            return
        }
        try {
            executor.execute {
                try {
                    body()
                } catch (e: Throwable) {
                    sendError(result, e)
                }
            }
        } catch (e: RejectedExecutionException) {
            sendError(result, e)
        }
    }

    private fun sendError(result: MainThreadResult, error: Throwable, method: String? = null) {
        StorageLog.e("Error while processing method call ${method ?: ""}", error)
        when {
            error is MethodCallException ->
                result.error(error.errorCode, error.errorMessage, error.errorDetails)

            error is CorruptedStorageDataException ->
                result.error("StorageError:CorruptedData", error.message, error.toCompleteString())

            error is InvalidatedStorageKeyException || error is KeyPermanentlyInvalidatedException ->
                result.error(
                    "StorageError:KeyInvalidated",
                    "The Android Keystore entry was invalidated. " +
                        "Recreate the storage and write the secret again.",
                    error.toCompleteString(),
                )

            else -> result.error("Unexpected Error", error.message, error.toCompleteString())
        }
    }

    /**
     * True when the keystore rejected a time-bound key because the user has to
     * (re)authenticate. Besides the documented [UserNotAuthenticatedException]
     * some devices report this wrapped in other keystore exceptions, so the
     * complete cause chain is checked.
     */
    private fun isUserNotAuthenticated(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            if (current is UserNotAuthenticatedException) return true
            if (current.message?.contains("not authenticated", ignoreCase = true) == true) return true
            current = current.cause
        }
        return false
    }

    private fun parseInitOptions(call: MethodCall): InitOptions {
        val options = call.argument<Map<String, Any?>>("options") ?: return InitOptions()
        return InitOptions(
            androidAuthenticationValidityDuration =
                (options["androidAuthenticationValidityDurationSeconds"] as? Number)
                    ?.toInt()?.seconds,
            authenticationRequired = options["authenticationRequired"] as? Boolean ?: true,
            androidBiometricOnly = options["androidBiometricOnly"] as? Boolean ?: true,
            silentWrites = options["silentWrites"] as? Boolean ?: false,
        )
    }

    /**
     * Lazy so the prompt info is only required (and validated) for calls that
     * actually end up showing a prompt.
     */
    private fun promptInfoProvider(call: MethodCall): () -> AndroidPromptInfo = {
        val info = requiredArgument<Map<String, Any?>>(call, PARAM_ANDROID_PROMPT_INFO)
        AndroidPromptInfo(
            title = info["title"] as? String
                ?: throw MethodCallException("MissingArgument", "androidPromptInfo is missing a 'title'."),
            subtitle = info["subtitle"] as? String,
            description = info["description"] as? String,
            negativeButton = info["negativeButton"] as? String
                ?: throw MethodCallException("MissingArgument", "androidPromptInfo is missing a 'negativeButton'."),
            confirmationRequired = info["confirmationRequired"] as? Boolean ?: true,
        )
    }

    private inline fun withStorage(
        call: MethodCall,
        result: MainThreadResult,
        body: (storage: BiometricVaultFile) -> Unit,
    ) {
        val name = requiredArgument<String>(call, PARAM_NAME)
        val storage = storageFiles[name] ?: run {
            StorageLog.w("Tried to access storage '$name' before it was initialized.")
            result.error("NoSuchStorage", "Storage $name was not initialized.", null)
            return
        }
        body(storage)
    }

    private fun <T> requiredArgument(call: MethodCall, name: String): T =
        call.argument<T>(name)
            ?: throw MethodCallException("MissingArgument", "Missing required argument '$name'")

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        updateAttachedActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        attachedActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        // The activity is recreated on configuration changes; keep the
        // reference fresh so prompts never target a destroyed activity.
        updateAttachedActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        attachedActivity = null
    }

    private fun updateAttachedActivity(activity: Activity) {
        if (activity !is FragmentActivity) {
            StorageLog.e(
                "Attached activity ${activity.javaClass.name} is not a FragmentActivity. " +
                    "Biometric prompts require FlutterFragmentActivity.",
            )
            attachedActivity = null
            return
        }
        attachedActivity = activity
    }

    /**
     * Guarantees every reply is delivered exactly once and on the main thread,
     * no matter which thread the storage or prompt callbacks finish on.
     */
    private inner class MainThreadResult(private val result: Result) : Result {

        private val replied = AtomicBoolean(false)

        override fun success(value: Any?) = reply { result.success(value) }

        override fun error(code: String, message: String?, details: Any?) =
            reply { result.error(code, message, details) }

        override fun notImplemented() = reply { result.notImplemented() }

        private fun reply(body: () -> Unit) {
            if (!replied.compareAndSet(false, true)) {
                StorageLog.w("Ignoring duplicate reply to a method call.")
                return
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                body()
            } else {
                mainHandler.post(body)
            }
        }
    }
}
