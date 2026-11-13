package com.farmitra.nearby

import com.farmitra.nearby.reply.ReplyIdentity
import org.junit.Assert.*
import org.junit.Test

class NotificationReplyIdentityTest {
    @Test fun repeatedCallbackRetainsOneMessageId() {
        assertEquals(ReplyIdentity.create("peer", "हाँ ठीक है 👍", "notification-1"),
            ReplyIdentity.create("peer", "हाँ ठीक है 👍", "notification-1"))
    }
    @Test fun sameTextOnAnotherNotificationIsANewReply() {
        assertNotEquals(ReplyIdentity.create("peer", "OK", "notification-1"),
            ReplyIdentity.create("peer", "OK", "notification-2"))
    }
    @Test fun recipientAndTextAreBoundToReplyId() {
        val original = ReplyIdentity.create("peer", "yes", "notification-1")
        assertNotEquals(original, ReplyIdentity.create("another-peer", "yes", "notification-1"))
        assertNotEquals(original, ReplyIdentity.create("peer", "no", "notification-1"))
    }
    @Test fun legacyNotificationsCanSendTheSameTextAgain() {
        assertNotEquals(ReplyIdentity.create("peer", "OK", null), ReplyIdentity.create("peer", "OK", null))
    }
}
