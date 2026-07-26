package com.brokeniptv.broken_iptv

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val deviceChannelName = "com.brokeniptv/device"
    private val pipChannelName = "com.brokeniptv/pip"
    private var pipChannel: MethodChannel? = null

    // Set from Dart: true only while a video is playing in phone mode, so
    // pressing Home drops into Picture-in-Picture instead of just
    // backgrounding. Never on TV (there PiP makes no sense).
    private var pipAllowed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "isTv") {
                    result.success(isRunningOnTv())
                } else {
                    result.notImplemented()
                }
            }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAllowed" -> {
                    pipAllowed = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "enter" -> result.success(enterPip())
                "isSupported" -> result.success(pipSupported())
                else -> result.notImplemented()
            }
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
            true
        } catch (e: Exception) {
            false
        }
    }

    // Home / recent-apps while a phone video is playing → floating window.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed) {
            enterPip()
        }
    }

    // Tell Dart so the player can drop its controls overlay while in the tiny
    // PiP window (and restore normal behaviour on the way out).
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    private fun isRunningOnTv(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val viaUiModeManager = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val viaConfiguration =
            (resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK) == Configuration.UI_MODE_TYPE_TELEVISION
        return viaUiModeManager || viaConfiguration
    }
}
