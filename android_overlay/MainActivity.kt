package PACKAGE_PLACEHOLDER

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "phone_cleaner/native"
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "requestAllFilesAccess" -> {
                        requestAllFilesAccess()
                        result.success(null)
                    }
                    "scanFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        if (paths.isNotEmpty()) {
                            MediaScannerConnection.scanFile(
                                this, paths.toTypedArray(), null, null
                            )
                        }
                        result.success(null)
                    }
                    "thumbnail" -> {
                        val path = call.argument<String>("path")
                        val size = call.argument<Int>("size") ?: 400
                        if (path == null) {
                            result.success(null)
                        } else {
                            executor.execute {
                                val bytes = try {
                                    makeThumbnail(path, size)
                                } catch (e: Exception) {
                                    null
                                }
                                mainHandler.post { result.success(bytes) }
                            }
                        }
                    }
                    "pdfThumb" -> {
                        val path = call.argument<String>("path")
                        val size = call.argument<Int>("size") ?: 200
                        if (path == null) {
                            result.success(null)
                        } else {
                            executor.execute {
                                val bytes = try {
                                    makePdfThumb(path, size)
                                } catch (e: Throwable) {
                                    null
                                }
                                mainHandler.post { result.success(bytes) }
                            }
                        }
                    }
                    "apkInfo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(null)
                        } else {
                            executor.execute {
                                val info = try {
                                    readApkInfo(path)
                                } catch (e: Throwable) {
                                    null
                                }
                                mainHandler.post { result.success(info) }
                            }
                        }
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        result.success(if (path == null) false else openFile(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    private fun makeThumbnail(path: String, size: Int): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val bitmap: Bitmap = ThumbnailUtils.createVideoThumbnail(
            File(path), Size(size, size), null
        )
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        return out.toByteArray()
    }

    private fun makePdfThumb(path: String, width: Int): ByteArray? {
        val pfd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        var renderer: PdfRenderer? = null
        try {
            renderer = PdfRenderer(pfd)
            if (renderer.pageCount == 0) return null
            val page = renderer.openPage(0)
            try {
                val w = width.coerceAtLeast(64)
                val h = (w.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                canvas.drawColor(Color.WHITE)
                page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 80, out)
                bmp.recycle()
                return out.toByteArray()
            } finally {
                page.close()
            }
        } finally {
            renderer?.close()
            pfd.close()
        }
    }

    private fun readApkInfo(path: String): Map<String, String>? {
        val pm = packageManager
        val info = pm.getPackageArchiveInfo(path, 0) ?: return null
        val app = info.applicationInfo ?: return null
        app.sourceDir = path
        app.publicSourceDir = path
        val label = app.loadLabel(pm).toString()
        return mapOf(
            "label" to label,
            "version" to (info.versionName ?: ""),
            "package" to info.packageName
        )
    }

    private fun openFile(path: String): Boolean {
        return try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val ext = file.extension.lowercase()
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Open with"))
            true
        } catch (e: Throwable) {
            false
        }
    }
}
