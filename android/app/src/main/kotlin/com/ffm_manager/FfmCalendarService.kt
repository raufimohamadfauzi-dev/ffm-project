package com.ffm_manager

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import android.util.Log
import java.util.TimeZone

/**
 * FfmCalendarService
 *
 * Layanan integrasi CalendarProvider Android untuk sinkronisasi pengingat tagihan
 * ke Google Calendar dan smartwatch.
 */
class FfmCalendarService(private val context: Context) {

    companion object {
        private const val TAG = "FfmCalendarService"
        private val CALENDAR_PROJECTION = arrayOf(
            Calendars._ID,
            Calendars.NAME,
            Calendars.ACCOUNT_NAME,
            Calendars.ACCOUNT_TYPE
        )

        /**
         * Memeriksa apakah kalender tersedia di perangkat
         */
        fun isAvailable(context: Context): Boolean {
            val calendars = getCalendars(context)
            return calendars.isNotEmpty()
        }

        /**
         * Mengambil ID kalender utama pengguna
         */
        fun getDefaultCalendarId(context: Context): Long? {
            val calendars = getCalendars(context)
            if (calendars.isEmpty()) return null

            // Prioritaskan kalender dengan nama yang mengandung "utama" atau "primary"
            val primaryCalendar = calendars.firstOrNull { 
                it.name.lowercase().contains("utama") || 
                it.name.lowercase().contains("primary") ||
                it.name.lowercase().contains("ffm")
            }

            if (primaryCalendar != null) return primaryCalendar.id

            // Fallback ke kalender pertama (biasanya Google Calendar utama)
            return calendars.firstOrNull()?.id
        }

        /**
         * Mengambil daftar kalender yang tersedia
         */
        private fun getCalendars(context: Context): List<CalendarInfo> {
            val calendars = mutableListOf<CalendarInfo>()
            val uri: Uri = Calendars.CONTENT_URI
            val selection = "((${Calendars.ACCOUNT_NAME} = ?) AND (${Calendars.ACCOUNT_TYPE} = ?) AND (${Calendars.OWNER_ACCOUNT} = ?))"
            val selectionArgs = arrayOf("", "com.google", "")

            val cursor: Cursor? = context.contentResolver.query(
                uri,
                CALENDAR_PROJECTION,
                null,
                null,
                Calendars._ID + " ASC"
            )

            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getLong(0)
                    val name = it.getString(1)
                    val accountName = it.getString(2)
                    val accountType = it.getString(3)
                    calendars.add(CalendarInfo(id, name, accountName, accountType))
                }
            }

            return calendars
        }
    }

    /**
     * Membuat event pengingat tagihan di kalender
     */
    fun createBillReminderEvent(
        title: String,
        description: String,
        dueDate: Long,
        amount: Double,
        category: String
    ): Map<String, Any?> {
        val calendarId = getDefaultCalendarId(context)
        if (calendarId == null) {
            Log.e(TAG, "Tidak ada kalender tersedia")
            return mapOf(
                "success" to false,
                "eventId" to null,
                "error" to "Tidak ada kalender tersedia"
            )
        }

        val values = ContentValues().apply {
            put(Events.CALENDAR_ID, calendarId)
            put(Events.TITLE, title)
            put(Events.DESCRIPTION, buildDescription(description, amount, category))
            put(Events.DTSTART, dueDate)
            put(Events.DTEND, dueDate + 3600000) // 1 jam durasi event
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(Events.HAS_ALARM, 1)
            put(Events.STATUS, Events.STATUS_CONFIRMED)
        }

        val uri: Uri? = try {
            context.contentResolver.insert(Events.CONTENT_URI, values)
        } catch (e: Exception) {
            Log.e(TAG, "Gagal membuat event kalender: ${e.message}")
            return mapOf(
                "success" to false,
                "eventId" to null,
                "error" to e.message
            )
        }

        if (uri == null) {
            return mapOf(
                "success" to false,
                "eventId" to null,
                "error" to "Gagal membuat event kalender"
            )
        }

        val eventId = ContentUris.parseId(uri)

        // Tambahkan reminder (15 menit sebelum)
        addReminder(eventId, 15)

        // Tambahkan reminder (1 jam sebelum)
        addReminder(eventId, 60)

        // Tambahkan reminder (1 hari sebelum)
        addReminder(eventId, 1440)

        return mapOf(
            "success" to true,
            "eventId" to eventId,
            "calendarId" to calendarId
        )
    }

    /**
     * Mengupdate event pengingat tagihan yang sudah ada
     */
    fun updateBillReminderEvent(
        eventId: Long,
        title: String,
        description: String,
        dueDate: Long,
        amount: Double,
        category: String
    ): Map<String, Any?> {
        val values = ContentValues().apply {
            put(Events.TITLE, title)
            put(Events.DESCRIPTION, buildDescription(description, amount, category))
            put(Events.DTSTART, dueDate)
            put(Events.DTEND, dueDate + 3600000)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }

        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, eventId)
        val rowsUpdated = try {
            context.contentResolver.update(uri, values, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Gagal mengupdate event kalender: ${e.message}")
            return mapOf(
                "success" to false,
                "eventId" to eventId,
                "error" to e.message
            )
        }

        return mapOf(
            "success" to (rowsUpdated > 0),
            "eventId" to eventId,
            "rowsUpdated" to rowsUpdated
        )
    }

    /**
     * Menghapus event pengingat tagihan dari kalender
     */
    fun deleteBillReminderEvent(eventId: Long): Map<String, Any?> {
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, eventId)
        val rowsDeleted = try {
            context.contentResolver.delete(uri, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Gagal menghapus event kalender: ${e.message}")
            return mapOf(
                "success" to false,
                "eventId" to eventId,
                "error" to e.message
            )
        }

        return mapOf(
            "success" to (rowsDeleted > 0),
            "eventId" to eventId,
            "rowsDeleted" to rowsDeleted
        )
    }

    /**
     * Mengambil daftar event dalam rentang tanggal
     */
    fun getBillReminders(startDate: Long, endDate: Long): List<Map<String, Any?>> {
        val reminders = mutableListOf<Map<String, Any?>>()

        val selection = "(${Events.DTSTART} >= ? AND ${Events.DTEND} <= ?)"
        val selectionArgs = arrayOf(startDate.toString(), endDate.toString())

        val cursor: Cursor? = context.contentResolver.query(
            Events.CONTENT_URI,
            arrayOf(
                Events._ID,
                Events.TITLE,
                Events.DESCRIPTION,
                Events.DTSTART,
                Events.DTEND
            ),
            selection,
            selectionArgs,
            Events.DTSTART + " ASC"
        )

        cursor?.use {
            while (it.moveToNext()) {
                val eventId = it.getLong(0)
                val title = it.getString(1)
                val description = it.getString(2)
                val dtStart = it.getLong(3)
                val dtEnd = it.getLong(4)

                reminders.add(mapOf(
                    "eventId" to eventId,
                    "title" to title,
                    "description" to description,
                    "dtStart" to dtStart,
                    "dtEnd" to dtEnd
                ))
            }
        }

        return reminders
    }

    /**
     * Menambahkan reminder untuk event
     */
    private fun addReminder(eventId: Long, minutesBefore: Int): Boolean {
        val values = ContentValues().apply {
            put(Reminders.MINUTES, minutesBefore)
            put(Reminders.METHOD, Reminders.METHOD_ALERT)
            put(Reminders.EVENT_ID, eventId)
        }

        val uri: Uri? = try {
            context.contentResolver.insert(Reminders.CONTENT_URI, values)
        } catch (e: Exception) {
            Log.e(TAG, "Gagal menambahkan reminder: ${e.message}")
            return false
        }

        return uri != null
    }

    /**
     * Membuat deskripsi event dengan informasi tagihan
     */
    private fun buildDescription(description: String, amount: Double, category: String): String {
        return """
            $description
            
            ---
            Kategori: $category
            Nominal: Rp ${String.format("%,.0f", amount)}
            
            (Pengingat otomatis dari FFM - Family Finance Manager)
        """.trimIndent()
    }
}

/**
 * Data class untuk informasi kalender
 */
data class CalendarInfo(
    val id: Long,
    val name: String,
    val accountName: String,
    val accountType: String
)