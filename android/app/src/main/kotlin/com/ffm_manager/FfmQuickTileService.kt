package com.ffm_manager

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * FfmQuickTileService
 *
 * TileService untuk menambahkan tombol "Catat FFM" di panel Control Center / Quick Settings
 * (bar notifikasi atas HP Android) untuk memicu Asisten AI / Catat Cepat dalam 1-ketukan.
 */
class FfmQuickTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(WIDGET_ACTION_EXTRA, "quick_note")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        tile.label = "Catat FFM"
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    companion object {
        private const val WIDGET_ACTION_EXTRA = "ffm_widget_action"
    }
}
