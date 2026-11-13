package com.farmitra.nearby.reply

import java.security.MessageDigest
import java.util.UUID

/** Same callback = same message ID; a fresh notification permits identical text. */
object ReplyIdentity {
    fun create(peer: String, text: String, nonce: String?): String {
        val identity = if (nonce.isNullOrEmpty()) UUID.randomUUID().toString()
            else MessageDigest.getInstance("SHA-256").digest("$nonce\u0000$peer\u0000$text".toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        return "notification-reply-$identity"
    }
}
