package app.blurr

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Journal en mémoire, copiable depuis l'écran : sert à diagnostiquer un échec sur un appareil précis. */
object AppLog {
    private const val TAG = "blurr"
    private val buffer = StringBuilder()
    private val format = SimpleDateFormat("HH:mm:ss.SSS", Locale.FRANCE)

    @Synchronized
    fun i(message: String) {
        Log.i(TAG, message)
        append("I", message)
    }

    @Synchronized
    fun e(message: String, error: Throwable? = null) {
        Log.e(TAG, message, error)
        val detail = if (error == null) message else "$message : ${error.javaClass.simpleName}: ${error.message}"
        append("E", detail)
    }

    @Synchronized
    fun dump(): String = buffer.toString()

    private fun append(level: String, message: String) {
        buffer.append(format.format(Date())).append(' ').append(level).append(' ').append(message).append('\n')
        if (buffer.length > 80_000) buffer.delete(0, 30_000)
    }
}
