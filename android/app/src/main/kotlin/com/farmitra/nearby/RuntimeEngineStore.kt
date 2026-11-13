package com.farmitra.nearby

/** One engine shared by the visible Activity and the foreground service.
 * Releasing either host must not destroy an engine still owned by the other.
 * Android calls these methods on its main thread.
 */
internal class RuntimeEngineStore<T>(
    private val create: (background: Boolean) -> T,
    private val destroy: (T) -> Unit
) {
    var engine: T? = null
        private set
    private var activityOwner: Any? = null
    private var serviceOwner: Any? = null

    val hasActivity: Boolean get() = activityOwner != null
    fun ownsActivity(owner: Any): Boolean = activityOwner === owner

    fun acquireActivity(owner: Any): T {
        activityOwner = owner
        return obtain(background = false)
    }

    fun acquireService(owner: Any): T {
        serviceOwner = owner
        return obtain(background = true)
    }

    fun releaseActivity(owner: Any) {
        if (activityOwner === owner) activityOwner = null
        releaseIfUnused()
    }

    fun releaseService(owner: Any) {
        if (serviceOwner === owner) serviceOwner = null
        releaseIfUnused()
    }

    private fun obtain(background: Boolean): T = engine ?: create(background).also { engine = it }

    private fun releaseIfUnused() {
        if (activityOwner != null || serviceOwner != null) return
        val unused = engine ?: return
        engine = null
        destroy(unused)
    }
}
