package com.messeya.chat

import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "flutter.native/helper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getHash") {
                val hash = getSignatureHash()
                if (hash != null) {
                    result.success(hash)
                } else {
                    result.error("UNAVAILABLE", "No se pudo obtener la firma.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getSignatureHash(): String? {
        try {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }

            val info = packageManager.getPackageInfo(packageName, flags)
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                info.signatures
            }

            if (signatures != null && signatures.isNotEmpty()) {
                val signature = signatures[0]
                val md = MessageDigest.getInstance("SHA1")
                md.update(signature.toByteArray())
                val digest = md.digest()
                val hexString = StringBuilder()
                for (i in digest.indices) {
                    val hex = Integer.toHexString(0xFF and digest[i].toInt())
                    if (hex.length == 1) hexString.append('0')
                    hexString.append(hex)
                    if (i < digest.size - 1) hexString.append(':')
                }
                return hexString.toString().uppercase()
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error obteniendo firma", e)
        }
        return null
    }
}
