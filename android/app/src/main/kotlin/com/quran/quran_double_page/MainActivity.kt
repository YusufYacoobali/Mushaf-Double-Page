package com.quran.quran_double_page

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Display
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import android.os.Bundle
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : AudioServiceActivity(), SensorEventListener {
    private var coverEvents: EventChannel.EventSink? = null
    private var coverChannel: EventChannel? = null
    private var resumed = false
    private var lastCover: Boolean? = null
    private val sensors get() = getSystemService(SENSOR_SERVICE) as SensorManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        coverChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mushaf_two_page/folded_cover").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    coverEvents = events
                    listenForCover()
                }
                override fun onCancel(arguments: Any?) {
                    coverEvents = null
                    sensors.unregisterListener(this@MainActivity)
                }
            })
        }
    }

    // Only inward-folding phones with an independent cover and a public hinge
    // sensor. An external display or an unknown hardware family proves nothing.
    private fun listenForCover() {
        if (coverEvents == null || !resumed) return
        lastCover = null
        if (Build.VERSION.SDK_INT >= 30 &&
            ((Build.MANUFACTURER.equals("Google", true) && Build.MODEL.startsWith("Pixel") &&
                Build.MODEL.endsWith(" Fold")) ||
             (Build.MANUFACTURER.equals("samsung", true) && Build.MODEL.startsWith("SM-F9")))) {
            val hinge = sensors.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
            if (hinge != null && sensors.registerListener(this, hinge, SensorManager.SENSOR_DELAY_NORMAL)) return
        }
        publishCover(false)
    }

    private fun publishCover(closed: Boolean) {
        if (closed != lastCover) coverEvents?.success(closed)
        lastCover = closed
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (resumed && Build.VERSION.SDK_INT >= 30 && event.sensor.type == Sensor.TYPE_HINGE_ANGLE) {
            publishCover(event.values[0] == 0f && display?.displayId == Display.DEFAULT_DISPLAY)
        }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onResume() {
        super.onResume()
        resumed = true
        listenForCover()
    }
    override fun onPause() {
        resumed = false
        sensors.unregisterListener(this)
        super.onPause()
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sensors.unregisterListener(this)
        coverChannel?.setStreamHandler(null)
        coverEvents = null
        coverChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPostResume() {
        super.onPostResume()
        hideStatusBar()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideStatusBar()
    }

    private fun hideStatusBar() {
        // Use the insets API so hiding also works with enforced edge-to-edge.
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.statusBars())
        }
    }
}
