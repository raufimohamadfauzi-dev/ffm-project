package com.ffm_manager

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class FfmWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val ACTION_EXTRA = "ffm_widget_action"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, FfmWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { appWidgetId ->
                updateWidget(context, manager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.ffm_widget)
            views.setTextViewText(R.id.ffm_widget_title, "FFM · Catatan keluarga")
            views.setTextViewText(
                R.id.ffm_widget_subtitle,
                "Input cepat, tetap tersimpan offline",
            )
            setAction(context, views, R.id.ffm_widget_transaction, "transaction")
            setAction(context, views, R.id.ffm_widget_scan, "scan")
            setAction(context, views, R.id.ffm_widget_activity, "activity")
            setAction(context, views, R.id.ffm_widget_budget, "budget")
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun setAction(
            context: Context,
            views: RemoteViews,
            viewId: Int,
            action: String,
        ) {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(ACTION_EXTRA, action)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(viewId, pendingIntent)
        }
    }
}
