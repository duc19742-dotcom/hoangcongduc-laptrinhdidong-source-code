package com.example.hoang_cong_duc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.AlertDialog
import android.hardware.fingerprint.FingerprintManager
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {
    private var cancellation: CancellationSignal? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "duc_attendance/fingerprint").setMethodCallHandler { call, result ->
            val manager = getSystemService(FingerprintManager::class.java)
            try {
                when (call.method) {
                    "available" -> result.success(manager != null && manager.isHardwareDetected && manager.hasEnrolledFingerprints())
                    "createKey" -> {
                        val alias = call.argument<String>("alias") ?: throw IllegalArgumentException()
                        require(alias.matches(Regex("duc_bio_[a-z0-9-]{1,80}")))
                        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                            .setDigests(KeyProperties.DIGEST_SHA256).setUserAuthenticationRequired(true)
                            .setInvalidatedByBiometricEnrollment(true)
                        if (android.os.Build.VERSION.SDK_INT >= 30) builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                        generator.initialize(builder.build())
                        result.success(Base64.encodeToString(generator.generateKeyPair().public.encoded, Base64.NO_WRAP))
                    }
                    "removeKey" -> {
                        val alias = call.argument<String>("alias") ?: throw IllegalArgumentException()
                        require(alias.startsWith("duc_bio_"))
                        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry(alias) }
                        result.success(null)
                    }
                    "sign" -> {
                        if (cancellation != null) { result.error("BUSY", "Đang xác thực vân tay.", null); return@setMethodCallHandler }
                        if (manager == null || !manager.isHardwareDetected || !manager.hasEnrolledFingerprints()) {
                            result.error("NOT_ENROLLED", "Hãy đăng ký vân tay trong Cài đặt điện thoại.", null); return@setMethodCallHandler
                        }
                        val alias = call.argument<String>("alias") ?: throw IllegalArgumentException()
                        val nonce = call.argument<String>("nonce") ?: throw IllegalArgumentException()
                        require(alias.startsWith("duc_bio_") && nonce.length in 1..256)
                        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                        val privateKey = store.getKey(alias, null) as? java.security.PrivateKey ?: throw IllegalStateException("KEY_MISSING")
                        val signature = Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey) }
                        val signal = CancellationSignal(); cancellation = signal
                        var completed = false
                        val dialog = AlertDialog.Builder(this).setTitle("Đăng nhập bằng vân tay")
                            .setMessage("Chạm ngón tay đã đăng ký lên cảm biến vân tay.")
                            .setNegativeButton("Hủy", null).create()
                        fun finish(value: String?, code: String? = null, message: String? = null) {
                            if (completed) return
                            completed = true; cancellation = null
                            signal.cancel(); dialog.dismiss()
                            if (code != null) result.error(code, message, null) else result.success(value)
                        }
                        dialog.setOnCancelListener { finish(null, "CANCELED", "Đã hủy xác thực vân tay.") }
                        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener { finish(null, "CANCELED", "Đã hủy xác thực vân tay.") } }
                        dialog.show()
                        manager.authenticate(FingerprintManager.CryptoObject(signature), signal, 0,
                            object : FingerprintManager.AuthenticationCallback() {
                                override fun onAuthenticationSucceeded(auth: FingerprintManager.AuthenticationResult) {
                                    try {
                                        val signer = auth.cryptoObject?.signature ?: throw IllegalStateException()
                                        signer.update(nonce.toByteArray(Charsets.UTF_8))
                                        finish(Base64.encodeToString(signer.sign(), Base64.NO_WRAP))
                                    } catch (_: Exception) { finish(null, "SIGN_FAILED", "Không ký được yêu cầu. Hãy bật lại đăng nhập vân tay.") }
                                }
                                override fun onAuthenticationFailed() { dialog.setMessage("Vân tay chưa khớp. Chạm lại hoặc bấm Hủy.") }
                                override fun onAuthenticationHelp(code: Int, text: CharSequence) { dialog.setMessage(text) }
                                override fun onAuthenticationError(code: Int, text: CharSequence) { finish(null, "AUTH_ERROR", text.toString()) }
                            }, Handler(Looper.getMainLooper()))
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                cancellation?.cancel(); cancellation = null
                result.error("KEY_INVALID", "Vân tay hoặc khóa thiết bị đã thay đổi. Đăng nhập bằng mật khẩu + OTP và bật lại vân tay.", null)
            }
        }
    }
    override fun onDestroy() { cancellation?.cancel(); cancellation = null; super.onDestroy() }
}
