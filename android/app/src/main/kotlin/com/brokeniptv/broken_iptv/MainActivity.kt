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
                    // Android 12+: the reliable path. With gesture navigation
                    // the system swipe-to-home does NOT call onUserLeaveHint,
                    // so auto-PiP has to be declared up-front instead.
                    updateAutoEnter()
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

    private fun pipParams(autoEnter: Boolean): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    /// Keeps the system's auto-enter flag in sync with [pipAllowed] (API 31+).
    /// Without this, swiping home with gesture navigation just backgrounds the
    /// app instead of floating the video — the reported "PiP doesn't work".
    private fun updateAutoEnter() {
        if (!pipSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            setPictureInPictureParams(pipParams(pipAllowed))
        } catch (e: Exception) {
            // Activity not in a state that accepts params: ignore.
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        // Already floating: nothing to do (and re-entering would throw).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) return true
        return try {
            // enterPictureInPictureMode returns false when the system refuses
            // (e.g. the per-app PiP permission is off in Settings) — report it
            // to Dart instead of failing silently.
            enterPictureInPictureMode(pipParams(pipAllowed))
        } catch (e: Exception) {
            false
        }
    }

    // Home / recent-apps with the 3-button navigation, and on API < 31.
    // On API 31+ with gestures the system handles it via setAutoEnterEnabled.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
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
