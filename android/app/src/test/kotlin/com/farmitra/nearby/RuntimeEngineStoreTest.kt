package com.farmitra.nearby

import org.junit.Assert.*
import org.junit.Test

class RuntimeEngineStoreTest {
    @Test fun recentsSwipeRetainsServiceEngineAndReopenReusesIt() {
        var created = 0
        var destroyed = 0
        val store = RuntimeEngineStore(create = { _: Boolean -> Any().also { created++ } },
            destroy = { _: Any -> destroyed++ })
        val activity = Any()
        val service = Any()
        val engine = store.acquireActivity(activity)
        assertSame(engine, store.acquireService(service))
        store.releaseActivity(activity)
        assertFalse(store.hasActivity)
        assertSame(engine, store.engine)
        assertEquals(0, destroyed)
        assertSame(engine, store.acquireActivity(Any()))
        assertEquals(1, created)
    }

    @Test fun serviceRestartBootstrapsWithoutAnActivity() {
        val starts = mutableListOf<Boolean>()
        val store = RuntimeEngineStore(create = { background: Boolean ->
            starts.add(background)
            Any()
        }, destroy = { _: Any -> })
        val service = Any()
        val engine = store.acquireService(service)
        assertEquals(listOf(true), starts)
        assertSame(engine, store.acquireService(service))
        assertSame(engine, store.acquireActivity(Any()))
        assertEquals(1, starts.size)
    }

    @Test fun backgroundOffReleasesEngineOnlyAfterActivityAlsoCloses() {
        var destroyed = 0
        val store = RuntimeEngineStore(create = { _: Boolean -> Any() },
            destroy = { _: Any -> destroyed++ })
        val activity = Any()
        val service = Any()
        store.acquireActivity(activity)
        store.acquireService(service)
        store.releaseService(service)
        assertNotNull(store.engine)
        assertEquals(0, destroyed)
        store.releaseActivity(activity)
        assertNull(store.engine)
        assertEquals(1, destroyed)
        store.releaseActivity(activity)
        store.releaseService(service)
        assertEquals(1, destroyed)
    }

    @Test fun oldActivityCleanupCannotReleaseANewActivitysEngine() {
        val store = RuntimeEngineStore(create = { _: Boolean -> Any() }, destroy = { _: Any -> })
        val oldActivity = Any()
        val newActivity = Any()
        val engine = store.acquireActivity(oldActivity)
        store.acquireActivity(newActivity)
        store.releaseActivity(oldActivity)
        assertTrue(store.ownsActivity(newActivity))
        assertSame(engine, store.engine)
    }
}
