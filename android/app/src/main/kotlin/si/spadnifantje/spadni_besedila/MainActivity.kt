package si.spadnifantje.spadni_besedila

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Brez tega zaklepa nekatere tablice zavržejo pakete, s katerimi se vodja oglaša na WiFi-ju.
    private var zaklep: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "si.spadnifantje/omrezje")
            .setMethodCallHandler { klic, rezultat ->
                if (klic.method == "multicast") {
                    if (klic.arguments == true) {
                        if (zaklep == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            zaklep = wifi.createMulticastLock("spadni").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                    } else {
                        zaklep?.release()
                        zaklep = null
                    }
                    rezultat.success(null)
                } else {
                    rezultat.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        zaklep?.release()
        zaklep = null
        super.onDestroy()
    }
}
