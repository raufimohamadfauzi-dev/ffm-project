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
        private const val PREFS = "ffm_widget_state"
        private const val TITLE_KEY = "title"
        private const val SUBTITLE_KEY = "subtitle"

        fun updateState(context: Context, title: String, subtitle: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(TITLE_KEY, title.take(80))
                .putString(SUBTITLE_KEY, subtitle.take(140))
                .apply()
            updateAll(context)
        }

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
            val state = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            views.setTextViewText(
                R.id.ffm_widget_title,
                state.getString(TITLE_KEY, "FFM · Asisten Offline"),
            )
            views.setTextViewText(
                R.id.ffm_widget_subtitle,
                state.getString(SUBTITLE_KEY, "Perintah cepat · tetap lokal"),
            )
            setAction(context, views, R.id.ffm_widget_assistant, "assistant")
            setAction(context, views, R.id.ffm_widget_summary, "summary")
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
