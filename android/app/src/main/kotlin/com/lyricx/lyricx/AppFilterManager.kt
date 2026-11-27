package com.lyricx.lyricx

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build

/**
 * Manages per-app blacklist/whitelist filtering for media session detection
 * and records packages that have posted active media sessions.
 */
object AppFilterManager {
    private const val PREFS_NAME = "app_filter_prefs"
    private const val KEY_MODE = "filter_mode"
    private const val KEY_BLACKLIST = "blacklist_packages"
    private const val KEY_WHITELIST = "whitelist_packages"
    private const val KEY_SEEN_PACKAGES = "seen_media_packages"

    const val MODE_OFF = "off"
    const val MODE_BLACKLIST = "blacklist"
    const val MODE_WHITELIST = "whitelist"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getMode(context: Context): String {
        val mode = prefs(context).getString(KEY_MODE, MODE_OFF) ?: MODE_OFF
        return when (mode) {
            MODE_BLACKLIST, MODE_WHITELIST -> mode
            else -> MODE_OFF
        }
    }

    fun getBlacklist(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_BLACKLIST, emptySet())?.toSet() ?: emptySet()

    fun getWhitelist(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_WHITELIST, emptySet())?.toSet() ?: emptySet()

    fun getSeenPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_SEEN_PACKAGES, emptySet())?.toSet() ?: emptySet()

    fun setFilter(
        context: Context,
        mode: String,
        blacklist: List<String>,
        whitelist: List<String>
    ) {
        val normalizedMode = when (mode) {
            MODE_BLACKLIST, MODE_WHITELIST -> mode
            else -> MODE_OFF
        }
        prefs(context).edit()
            .putString(KEY_MODE, normalizedMode)
            .putStringSet(KEY_BLACKLIST, blacklist.map { it.trim() }.filter { it.isNotEmpty() }.toSet())
            .putStringSet(KEY_WHITELIST, whitelist.map { it.trim() }.filter { it.isNotEmpty() }.toSet())
            .apply()
    }

    fun recordSeenPackages(context: Context, packages: Collection<String>, ownPackage: String) {
        if (packages.isEmpty()) return
        val existing = getSeenPackages(context)
        val additions = packages.filter { it.isNotBlank() && it != ownPackage && !existing.contains(it) }
        if (additions.isEmpty()) return
        prefs(context).edit()
            .putStringSet(KEY_SEEN_PACKAGES, existing + additions)
            .apply()
    }

    fun isPackageAllowed(
        context: Context,
        pkg: String?,
        ownPackage: String,
        requireSupportedOrMediaInDefaultMode: Boolean = false,
        isSupportedOrMedia: (String) -> Boolean = { true }
    ): Boolean {
        if (pkg.isNullOrBlank() || pkg == ownPackage) return false
        return when (getMode(context)) {
            MODE_WHITELIST -> getWhitelist(context).contains(pkg)
            MODE_BLACKLIST -> {
                if (getBlacklist(context).contains(pkg)) return false
                if (requireSupportedOrMediaInDefaultMode) isSupportedOrMedia(pkg) else true
            }
            else -> {
                if (requireSupportedOrMediaInDefaultMode) isSupportedOrMedia(pkg) else true
            }
        }
    }

    fun getInstalledApps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val ownPackage = context.packageName
        val seenPackages = getSeenPackages(context)
        val appsByPackage = linkedMapOf<String, MutableMap<String, Any>>()

        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(launcherIntent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcherIntent, 0)
        }

        for (info in resolveInfos) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == ownPackage || appsByPackage.containsKey(pkg)) continue
            val label = info.loadLabel(pm)?.toString()?.trim().orEmpty().ifEmpty { pkg }
            appsByPackage[pkg] = mutableMapOf(
                "packageName" to pkg,
                "appName" to label,
                "isSeenMedia" to seenPackages.contains(pkg)
            )
        }

        for (pkg in seenPackages) {
            if (pkg == ownPackage || appsByPackage.containsKey(pkg)) continue
            val label = try {
                val appInfo: ApplicationInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0L))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getApplicationInfo(pkg, 0)
                }
                pm.getApplicationLabel(appInfo).toString().trim().ifEmpty { pkg }
            } catch (_: Exception) {
                pkg
            }
            appsByPackage[pkg] = mutableMapOf(
                "packageName" to pkg,
                "appName" to label,
                "isSeenMedia" to true
            )
        }

        return appsByPackage.values.sortedWith(
            compareByDescending<Map<String, Any>> { it["isSeenMedia"] as Boolean }
                .thenBy { (it["appName"] as String).lowercase() }
        )
    }
}
