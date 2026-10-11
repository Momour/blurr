package app.blurr

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.core.content.IntentCompat
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import org.opencv.android.OpenCVLoader
import java.io.File
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Écran unique : choisir une vidéo, régler la détection, lancer le masquage (analyse puis export), ouvrir ou partager.
 * Tout le traitement se fait dans l'application, hors connexion.
 */
@OptIn(markerClass = [UnstableApi::class, ExperimentalApi::class])
class MainActivity : ComponentActivity() {

    private enum class Phase { IDLE, ANALYZING, EXPORTING, VERIFYING, SAVING }

    private class Summary(
        val frames: Int,
        val framesWithFaces: Int,
        val detections: Int,
        val avgMs: Double,
        val usedFallback: Boolean,
        val plan: MaskPlan.Stats,
    )

    private val ui = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val cancelRequested = AtomicBoolean(false)
    private lateinit var exporter: Exporter

    private var phase = Phase.IDLE
    private var selectedUri: Uri? = null
    private var selectedInfo: VideoInfo? = null
    private var plan: MaskPlan? = null
    private var runOptions: Options? = null
    private var summary: Summary? = null
    private var saved: MediaStoreSaver.Saved? = null
    private var verification: Verifier.Result? = null
    private var exportedFrames = 0
    private var hdrAttempt = 0
    private var usedForcedSdr = false

    private lateinit var pickButton: Button
    private lateinit var infoText: TextView
    private lateinit var optionsBox: LinearLayout
    private lateinit var qualityGroup: RadioGroup
    private lateinit var sensitivityGroup: RadioGroup
    private lateinit var styleGroup: RadioGroup
    private lateinit var startButton: Button
    private lateinit var progressBar: ProgressBar
    private lateinit var statusText: TextView
    private lateinit var cancelButton: Button
    private lateinit var resultBox: LinearLayout
    private lateinit var resultText: TextView
    private lateinit var openButton: Button
    private lateinit var shareButton: Button
    private var statusDefaultColors: ColorStateList? = null

    private val pickVideo = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) onVideoChosen(uri)
    }

    // ------------------------------------------------------------------ cycle de vie

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        exporter = Exporter(this)
        buildUi()
        refreshUi()
        addOnNewIntentListener { handleIntent(it) }
        handleIntent(intent)
    }

    override fun onDestroy() {
        cancelRequested.set(true)
        exporter.cancel()
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("video/") != true) return
        val uri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java) ?: return
        if (phase == Phase.IDLE) onVideoChosen(uri)
    }

    // ------------------------------------------------------------------ choix de la vidéo

    private fun onVideoChosen(uri: Uri) {
        if (phase != Phase.IDLE) return
        setStatus("Lecture de la vidéo...")
        worker.execute {
            try {
                val info = VideoProbe.read(this, uri)
                ui.post {
                    selectedUri = uri
                    selectedInfo = info
                    plan = null
                    summary = null
                    saved = null
                    logDeviceHeader()
                    AppLog.i(
                        "Vidéo : ${info.mime} ${info.codedWidth}x${info.codedHeight} rotation ${info.rotation}, " +
                            "${info.frameRate} i/s annoncées, ${info.durationUs / 1000} ms, ${info.bitrate} b/s, " +
                            "HDR=${info.isHdr}, son=${info.hasAudio}",
                    )
                    setStatus("Réglez la détection si besoin, puis lancez le masquage.")
                    refreshUi()
                }
            } catch (t: Throwable) {
                AppLog.e("Lecture de la vidéo impossible", t)
                ui.post {
                    selectedUri = null
                    selectedInfo = null
                    setStatus("Vidéo illisible : ${t.message ?: t.javaClass.simpleName}", error = true)
                    refreshUi()
                }
            }
        }
    }

    // ------------------------------------------------------------------ traitement

    private fun startProcessing() {
        val uri = selectedUri ?: return
        val info = selectedInfo ?: return
        if (phase != Phase.IDLE) return
        if (info.codedWidth <= 0 || info.codedHeight <= 0) {
            setStatus("Dimensions de la vidéo inconnues.", error = true)
            return
        }

        val bitrate = EncodingPolicy.videoBitrate(info.displayWidth, info.displayHeight, info.frameRate, info.bitrate)
        val needed = EncodingPolicy.estimatedOutputBytes(info.durationUs, bitrate) * 2 + 50L * 1024 * 1024
        val free = cacheDir.usableSpace
        if (free < needed) {
            setStatus(
                "Espace insuffisant : environ ${Formatter.formatShortFileSize(this, needed)} nécessaires, " +
                    "${Formatter.formatShortFileSize(this, free)} libres.",
                error = true,
            )
            return
        }

        val options = currentOptions()
        runOptions = options
        cancelRequested.set(false)
        hdrAttempt = 0
        usedForcedSdr = false
        plan = null
        summary = null
        saved = null
        verification = null
        exportedFrames = 0
        phase = Phase.ANALYZING
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setStatus("Préparation de la détection...")
        refreshUi()
        val t = options.tracking
        AppLog.i(
            "--- Traitement : analyse ${options.analysisMaxSide} px, sensibilité ${options.sensitivity} (seuil ${t.keepThreshold}, " +
                "confirmation ${t.confirmThreshold}, ${t.minHits} détection(s) min.), rendu ${options.style}, " +
                "masque x${options.maskScale}, marge ${options.marginFrames} images ---",
        )

        worker.execute {
            var detector: YuNetDetector? = null
            try {
                if (!OpenCVLoader.initLocal()) {
                    throw IllegalStateException("OpenCV n'a pas pu être chargé (bibliothèque native absente pour ce processeur)")
                }
                detector = YuNetDetector(this, options.tracking.keepThreshold)
                val result = Analyzer.run(
                    context = this,
                    uri = uri,
                    info = info,
                    options = options,
                    detector = detector,
                    onProgress = { fraction, frames, msPerFrame ->
                        ui.post {
                            if (phase == Phase.ANALYZING) {
                                showProgress(
                                    "Étape 1/2 : détection des visages",
                                    fraction,
                                    "$frames images, ${String.format(Locale.getDefault(), "%.0f", msPerFrame)} ms par image",
                                )
                            }
                        }
                    },
                    isCancelled = { cancelRequested.get() },
                )
                val built = MaskPlan.build(
                    detections = result.detections,
                    params = options.tracking,
                    maskScale = options.maskScale,
                    marginFrames = options.marginFrames,
                    aspect = info.displayWidth.toFloat() / info.displayHeight,
                )
                val s = Summary(
                    frames = result.frames,
                    framesWithFaces = result.detections.framesWithFaces,
                    detections = result.detections.totalFaces,
                    avgMs = result.avgDetectMs,
                    usedFallback = result.usedFallback,
                    plan = built.stats,
                )
                ui.post { onAnalysisDone(s, built) }
            } catch (c: Analyzer.Cancelled) {
                ui.post { onCancelled() }
            } catch (t: Throwable) {
                AppLog.e("Analyse échouée", t)
                ui.post { fail("Analyse impossible : ${t.message ?: t.javaClass.simpleName}") }
            } finally {
                try {
                    detector?.close()
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun onAnalysisDone(s: Summary, built: MaskPlan) {
        if (cancelRequested.get() || phase != Phase.ANALYZING) return
        if (s.frames == 0) {
            fail("Aucune image n'a pu être décodée. Consultez le journal.")
            return
        }
        summary = s
        plan = built
        AppLog.i(
            "Plan de masquage : ${built.frameCount} images, ${s.framesWithFaces} avec détection, ${s.detections} détections, " +
                "${s.plan.tracks} pistes dont ${s.plan.confirmedTracks} masquées, ${s.plan.maskedFrames} images masquées",
        )
        startExport()
    }

    private fun startExport() {
        val uri = selectedUri ?: return
        val info = selectedInfo ?: return
        val p = plan ?: return
        val options = runOptions ?: return

        val hdrMode = when {
            !info.isHdr -> Composition.HDR_MODE_KEEP_HDR
            hdrAttempt == 0 -> Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL
            else -> Composition.HDR_MODE_EXPERIMENTAL_FORCE_INTERPRET_HDR_AS_SDR
        }
        usedForcedSdr = info.isHdr && hdrAttempt > 0
        phase = Phase.EXPORTING
        setStatus("Étape 2/2 : préparation de l'export...")
        refreshUi()
        AppLog.i("Export : mode HDR $hdrMode (tentative ${hdrAttempt + 1})")
        try {
            exporter.start(uri, info, p, options.style, hdrMode, exportCallback)
        } catch (t: Throwable) {
            AppLog.e("Démarrage de l'export impossible", t)
            fail("Export impossible : ${t.message ?: t.javaClass.simpleName}")
        }
    }

    private val exportCallback = object : Exporter.Callback {
        override fun onProgress(fraction: Float) {
            if (phase == Phase.EXPORTING) showProgress("Étape 2/2 : export de la vidéo", fraction, null)
        }

        override fun onCompleted(output: File, result: ExportResult) {
            if (phase != Phase.EXPORTING) {
                output.delete()
                return
            }
            exportedFrames = result.videoFrameCount
            phase = Phase.VERIFYING
            setStatus("Étape 3/3 : contrôle du résultat...")
            refreshUi()
            val sourceName = selectedInfo?.name ?: "video"
            val checkPlan = plan
            val checkOptions = runOptions
            worker.execute {
                try {
                    // Contrôle : relecture de la vidéo produite. Une panne ici ne doit jamais empêcher l'enregistrement.
                    var check: Verifier.Result? = null
                    try {
                        check = Verifier.run(
                            context = this@MainActivity,
                            file = output,
                            plan = checkNotNull(checkPlan),
                            options = checkNotNull(checkOptions),
                            onProgress = { fraction ->
                                ui.post {
                                    if (phase == Phase.VERIFYING) showProgress("Étape 3/3 : contrôle du résultat", fraction, null)
                                }
                            },
                            isCancelled = { cancelRequested.get() },
                        )
                    } catch (t: Throwable) {
                        AppLog.e("Contrôle du résultat impossible", t)
                    }
                    if (cancelRequested.get()) {
                        ui.post { onCancelled() }
                        return@execute
                    }
                    ui.post {
                        phase = Phase.SAVING
                        setStatus("Enregistrement dans la galerie...")
                        refreshUi()
                    }
                    val s = MediaStoreSaver.save(this@MainActivity, output, sourceName)
                    ui.post { onSaved(s, check) }
                } catch (t: Throwable) {
                    AppLog.e("Enregistrement impossible", t)
                    ui.post { fail("Enregistrement impossible : ${t.message ?: t.javaClass.simpleName}") }
                } finally {
                    output.delete()
                }
            }
        }

        override fun onError(error: ExportException) {
            AppLog.e("Export échoué (${error.errorCodeName})", error)
            val info = selectedInfo
            if (phase == Phase.EXPORTING && info != null && info.isHdr && hdrAttempt == 0) {
                hdrAttempt = 1
                AppLog.i("Nouvelle tentative : interprétation de secours HDR vers SDR")
                startExport()
            } else {
                fail("Export impossible (${error.errorCodeName}). Consultez le journal.")
            }
        }
    }

    private fun onSaved(s: MediaStoreSaver.Saved, check: Verifier.Result?) {
        phase = Phase.IDLE
        saved = s
        verification = check
        releaseScreen()
        val a = summary
        val text = StringBuilder()
        text.append("Terminé.\n")
        text.append("Fichier : ${MediaStoreSaver.RELATIVE_PATH}/${s.displayName} (${Formatter.formatShortFileSize(this, s.sizeBytes)}).\n")
        if (a != null) {
            val pct = if (a.frames > 0) 100.0 * a.framesWithFaces / a.frames else 0.0
            val masked = if (a.frames > 0) 100.0 * a.plan.maskedFrames / a.frames else 0.0
            text.append(
                "Détections brutes sur ${a.framesWithFaces} images sur ${a.frames} " +
                    "(${String.format(Locale.getDefault(), "%.0f", pct)} %). " +
                    "${a.plan.confirmedTracks} piste(s) de visage masquée(s), ${a.plan.rejectedTracks} piste(s) non " +
                    "confirmée(s) écartée(s) (faux positifs probables). Images masquées : " +
                    "${String.format(Locale.getDefault(), "%.0f", masked)} %.\n",
            )
            if (a.plan.confirmedTracks == 0) {
                text.append("ATTENTION : aucun visage confirmé, la vidéo n'a reçu aucun masque. Essayez la sensibilité maximale.\n")
            }
            if (a.usedFallback) text.append("Analyse en mode de repli (plus lent, moins précis).\n")
            val tolerance = maxOf(2, a.frames / 50)
            if (exportedFrames > 0 && kotlin.math.abs(exportedFrames - a.frames) > tolerance) {
                text.append(
                    "Note : ${a.frames} images analysées contre $exportedFrames exportées. " +
                        "Si les masques semblent décalés dans le temps, signalez-le avec le journal.\n",
                )
            }
        }
        val c = check
        if (c == null) {
            text.append("Contrôle automatique du résultat : non effectué.\n")
        } else if (c.framesWithFaces == 0) {
            text.append("Contrôle automatique : ${c.sampledFrames} images de la vidéo produite relues, aucun visage détectable hors des zones masquées.\n")
        } else {
            text.append(
                "ATTENTION, contrôle automatique : un visage reste détectable hors des zones masquées sur " +
                    "${c.framesWithFaces} des ${c.sampledFrames} images relues. Regardez attentivement ces passages.\n",
            )
        }
        if (usedForcedSdr) text.append("HDR converti en SDR par la méthode de secours : les couleurs peuvent paraître ternes.\n")
        text.append("Les coordonnées GPS et les métadonnées de la source ne sont pas recopiées.\n")
        text.append("Regardez la vidéo en entier avant de la diffuser : aucun détecteur ne trouve 100 % des visages (profils, petits visages, flou, contre-jour).")
        resultText.text = text.toString()
        setStatus("Terminé.")
        refreshUi()
        AppLog.i("Terminé : ${s.displayName}")
    }

    private fun cancelProcessing() {
        when (phase) {
            Phase.ANALYZING -> {
                cancelRequested.set(true)
                setStatus("Annulation...")
            }
            Phase.EXPORTING -> {
                cancelRequested.set(true)
                exporter.cancel()
                onCancelled()
            }
            Phase.VERIFYING -> {
                cancelRequested.set(true)
                setStatus("Annulation...")
            }
            else -> Unit
        }
    }

    private fun onCancelled() {
        phase = Phase.IDLE
        releaseScreen()
        setStatus("Annulé.")
        refreshUi()
        AppLog.i("Annulé par l'utilisateur")
    }

    private fun fail(message: String) {
        phase = Phase.IDLE
        releaseScreen()
        setStatus(message, error = true)
        refreshUi()
    }

    private fun releaseScreen() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun currentOptions(): Options {
        val sizes = intArrayOf(960, 1280, 1920)
        val sensitivities = Sensitivity.entries
        val styles = MaskStyle.entries
        return Options(
            analysisMaxSide = sizes[selectedIndex(qualityGroup).coerceIn(0, sizes.lastIndex)],
            sensitivity = sensitivities[selectedIndex(sensitivityGroup).coerceIn(0, sensitivities.lastIndex)],
            style = styles[selectedIndex(styleGroup).coerceIn(0, styles.lastIndex)],
        )
    }

    private fun selectedIndex(group: RadioGroup): Int {
        val checked = group.findViewById<View>(group.checkedRadioButtonId) ?: return 0
        return group.indexOfChild(checked)
    }

    // ------------------------------------------------------------------ résultat

    private fun openResult() {
        val s = saved ?: return
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(s.uri, "video/mp4")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(this, "Aucune application pour lire la vidéo. Ouvrez-la depuis la galerie.", Toast.LENGTH_LONG).show()
        }
    }

    private fun shareResult() {
        val s = saved ?: return
        val send = Intent(Intent.ACTION_SEND)
            .setType("video/mp4")
            .putExtra(Intent.EXTRA_STREAM, s.uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, "Partager la vidéo floutée"))
    }

    private fun copyLog() {
        val clipboard = getSystemService(ClipboardManager::class.java)
        clipboard.setPrimaryClip(ClipData.newPlainText("journal blurr", AppLog.dump()))
        Toast.makeText(this, "Journal copié. Collez-le dans un message.", Toast.LENGTH_LONG).show()
    }

    private fun logDeviceHeader() {
        val version = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (_: Exception) {
            "?"
        }
        AppLog.i(
            "blurr $version | ${Build.MANUFACTURER} ${Build.MODEL} | Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) | " +
                "ABI ${Build.SUPPORTED_ABIS.joinToString()}",
        )
    }

    // ------------------------------------------------------------------ interface

    private fun refreshUi() {
        val busy = phase != Phase.IDLE
        val info = selectedInfo

        pickButton.isEnabled = !busy
        infoText.visibility = if (info != null) View.VISIBLE else View.GONE
        infoText.text = info?.let { describe(it) } ?: ""
        optionsBox.visibility = if (info != null) View.VISIBLE else View.GONE
        setChildrenEnabled(qualityGroup, !busy)
        setChildrenEnabled(sensitivityGroup, !busy)
        setChildrenEnabled(styleGroup, !busy)
        startButton.isEnabled = !busy && info != null
        progressBar.visibility = if (busy) View.VISIBLE else View.GONE
        cancelButton.visibility = if (phase == Phase.ANALYZING || phase == Phase.EXPORTING || phase == Phase.VERIFYING) View.VISIBLE else View.GONE
        resultBox.visibility = if (saved != null && !busy) View.VISIBLE else View.GONE
        if (phase == Phase.SAVING) {
            progressBar.isIndeterminate = true
        } else if (progressBar.isIndeterminate) {
            progressBar.isIndeterminate = false
        }
    }

    private fun setChildrenEnabled(group: ViewGroup, enabled: Boolean) {
        for (i in 0 until group.childCount) group.getChildAt(i).isEnabled = enabled
    }

    private fun setStatus(text: String, error: Boolean = false) {
        statusText.text = text
        if (error) {
            statusText.setTextColor(ERROR_COLOR)
        } else {
            statusDefaultColors?.let { statusText.setTextColor(it) }
        }
    }

    private fun showProgress(label: String, fraction: Float, detail: String?) {
        progressBar.progress = (fraction.coerceIn(0f, 1f) * PROGRESS_MAX).toInt()
        val percent = (fraction.coerceIn(0f, 1f) * 100).toInt()
        setStatus(if (detail == null) "$label : $percent %" else "$label : $percent % ($detail)")
    }

    private fun describe(info: VideoInfo): String {
        val codec = when {
            info.mime.contains("hevc", ignoreCase = true) -> "HEVC"
            info.mime.contains("avc", ignoreCase = true) -> "H.264"
            info.mime.contains("av01", ignoreCase = true) -> "AV1"
            info.mime.contains("vp9", ignoreCase = true) -> "VP9"
            else -> info.mime
        }
        val fps = if (info.frameRate > 0f) String.format(Locale.getDefault(), "%.0f i/s", info.frameRate) else "cadence inconnue"
        val rate = if (info.bitrate > 0) String.format(Locale.getDefault(), "%.1f Mb/s", info.bitrate / 1_000_000.0) else "débit inconnu"
        return buildString {
            append(info.name).append('\n')
            append("${info.displayWidth} x ${info.displayHeight}, $codec, $fps, ${formatDuration(info.durationUs)}, $rate\n")
            append(if (info.hasAudio) "Son : conservé" else "Son : aucun")
            if (info.isHdr) append("\nHDR : sera converti en SDR")
        }
    }

    private fun formatDuration(us: Long): String {
        val total = (us / 1_000_000).toInt()
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s) else String.format(Locale.getDefault(), "%d:%02d", m, s)
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(32))
        }

        root.add(TextView(this).apply {
            text = "blurr"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, top = 0)
        root.add(TextView(this).apply {
            text = "Floute les visages d'une vidéo. Tout est traité sur ce téléphone, sans Internet."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        }, top = 4)

        pickButton = Button(this).apply {
            text = "Choisir une vidéo"
            setOnClickListener {
                pickVideo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
            }
        }
        root.add(pickButton, top = 20)

        infoText = TextView(this).apply { setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f) }
        root.add(infoText, top = 8)

        optionsBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        qualityGroup = optionsBox.addChoice(
            "Précision de l'analyse (plus précis = plus lent)",
            listOf("Rapide (960 px)", "Standard (1280 px)", "Précis (1920 px)"),
            defaultIndex = 1,
        )
        sensitivityGroup = optionsBox.addChoice(
            "Sensibilité (plus sensible = moins de visages manqués, plus de faux masques)",
            listOf("Normale (moins de faux masques)", "Élevée", "Maximale (moins de visages manqués)"),
            defaultIndex = 1,
        )
        // Même ordre que MaskStyle : BLUR, BLACK.
        styleGroup = optionsBox.addChoice(
            "Rendu",
            listOf("Flou", "Masque noir (protection la plus sûre)"),
            defaultIndex = 0,
        )
        root.add(optionsBox, top = 12)

        startButton = Button(this).apply {
            text = "Masquer les visages"
            setOnClickListener { startProcessing() }
        }
        root.add(startButton, top = 16)

        root.add(TextView(this).apply {
            text = "Laissez l'application ouverte et l'écran allumé pendant le traitement."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }, top = 4)

        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = PROGRESS_MAX
            isIndeterminate = false
        }
        root.add(progressBar, top = 16)

        statusText = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            text = "Choisissez une vidéo pour commencer."
        }
        statusDefaultColors = statusText.textColors
        root.add(statusText, top = 6)

        cancelButton = Button(this).apply {
            text = "Annuler"
            setOnClickListener { cancelProcessing() }
        }
        root.add(cancelButton, top = 8)

        resultBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        resultText = TextView(this).apply { setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f) }
        resultBox.add(resultText, top = 0)
        openButton = Button(this).apply {
            text = "Ouvrir la vidéo"
            setOnClickListener { openResult() }
        }
        resultBox.add(openButton, top = 12)
        shareButton = Button(this).apply {
            text = "Partager"
            setOnClickListener { shareResult() }
        }
        resultBox.add(shareButton, top = 4)
        root.add(resultBox, top = 16)

        val logButton = Button(this).apply {
            text = "Copier le journal (diagnostic)"
            setOnClickListener { copyLog() }
        }
        root.add(logButton, top = 28)

        setContentView(ScrollView(this).apply {
            isFillViewport = true
            addView(root)
        })
    }

    private fun <T : View> LinearLayout.add(view: T, top: Int): T {
        val params = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        params.topMargin = dp(top)
        addView(view, params)
        return view
    }

    private fun LinearLayout.addChoice(title: String, labels: List<String>, defaultIndex: Int): RadioGroup {
        add(
            TextView(context).apply {
                text = title
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            },
            top = 12,
        )
        val group = RadioGroup(context).apply { orientation = LinearLayout.VERTICAL }
        val ids = labels.map { label ->
            val button = RadioButton(context).apply {
                text = label
                id = View.generateViewId()
            }
            group.addView(button)
            button.id
        }
        group.check(ids[defaultIndex])
        add(group, top = 2)
        return group
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private companion object {
        const val PROGRESS_MAX = 1000
        const val ERROR_COLOR = 0xFFB3261E.toInt()
    }
}
