package com.example.flutter_application_1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

class SkinAIHomeWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    val snapshot = runCatching {
      JSONObject(widgetData.getString("skinai_snapshot", "{}") ?: "{}")
    }.getOrDefault(JSONObject())
    val style = snapshot.optString("style", "dailyProgress")
    val accent = snapshot.optLong("accentColor", 0xFF168CFF).toInt()
    val configuredTheme = snapshot.optString("theme", "system")
    val labels = try {
      snapshot.getJSONObject("labels")
    } catch (_: Exception) {
      JSONObject()
    }
    val systemDark =
      context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
    val background = when {
      style == "eveningRoutine" -> Color.rgb(28, 34, 62)
      configuredTheme == "dark" ||
        (configuredTheme == "system" && systemDark) -> Color.rgb(21, 28, 44)
      else -> Color.WHITE
    }
    val foreground =
      if (background == Color.WHITE) Color.rgb(23, 32, 51) else Color.WHITE
    val progress = if (snapshot.optString("dataPeriod", "daily") == "weekly") {
      snapshot.optInt("weeklyProgress", 0)
    } else {
      snapshot.optInt("progressToday", 0)
    }.coerceIn(0, 100)
    val showProgress = snapshot.optBoolean("showProgress", true)
    val showTasks = snapshot.optBoolean("showTasks", true)
    val compact = snapshot.optBoolean("compact", false)
    val task = snapshot.optString("nextTask", "")
    val streak = snapshot.optInt("streak", 0)
    val tasks = try {
      JSONArray(snapshot.optString("tasks", "[]"))
    } catch (_: Exception) {
      JSONArray()
    }

    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.skinai_widget).apply {
        setInt(R.id.widget_root, "setBackgroundColor", background)
        setTextColor(R.id.widget_brand, accent)
        setTextColor(R.id.widget_title, foreground)
        setTextColor(R.id.widget_summary, foreground)
        setTextColor(R.id.widget_task, foreground)
        setProgressBar(R.id.widget_progress, 100, progress, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          setColorStateList(
            R.id.widget_progress,
            "setProgressTintList",
            ColorStateList.valueOf(accent),
          )
        }
        setTextViewText(R.id.widget_brand, labels.optString("brand", "SkinAI"))
        setTextViewText(
          R.id.widget_summary,
          "$progress% ${labels.optString("complete", "complete")}",
        )

        val title = when (style) {
          "morningRoutine" -> labels.optString("morning", "Morning routine")
          "eveningRoutine" -> labels.optString("evening", "Evening routine")
          "weeklyRoutine" -> labels.optString("weekly", "Your week")
          "minimal" -> "$progress%"
          "statistics" ->
            "$streak ${labels.optString("dayStreak", "day streak")}"
          "quickActions" -> labels.optString("quickActions", "Quick actions")
          else -> labels.optString("dailyProgress", "Today's progress")
        }
        setTextViewText(R.id.widget_title, title)
        setTextViewText(
          R.id.widget_task,
          when (style) {
            "morningRoutine" -> firstTask(tasks, task)
            "eveningRoutine" ->
              labels.optString("eveningHint", "A few calm steps for tonight")
            "weeklyRoutine" ->
              "${snapshot.optInt("weeklyCompleted", 0)} of " +
                "${snapshot.optInt("weeklyTotal", 0)} tasks this week"
            "statistics" ->
              "${snapshot.optInt("consistency", 0)}% " +
                labels.optString("consistency", "consistency")
            "quickActions" -> "Tap a shortcut to get started"
            else -> if (task.isBlank()) labels.optString("noTask", "No tasks today") else task
          },
        )
        setViewVisibility(
          R.id.widget_progress,
          if (showProgress && style != "minimal") View.VISIBLE else View.GONE,
        )
        setViewVisibility(
          R.id.widget_task,
          if (showTasks || style == "statistics") View.VISIBLE else View.GONE,
        )
        setViewPadding(
          R.id.widget_root,
          if (compact) 24 else 36,
          if (compact) 20 else 28,
          if (compact) 24 else 36,
          if (compact) 20 else 28,
        )
        setViewVisibility(
          R.id.widget_actions,
          if (style == "quickActions") View.VISIBLE else View.GONE,
        )
        setTextViewText(
          R.id.widget_daily_action,
          labels.optString("dailyAction", "Daily"),
        )
        setTextViewText(
          R.id.widget_weekly_action,
          labels.optString("weeklyAction", "Weekly"),
        )
        setTextViewText(
          R.id.widget_scan_action,
          labels.optString("scanAction", "Scan"),
        )

        val rootUri = if (style == "weeklyRoutine") {
          Uri.parse("skinai://routine/weekly")
        } else {
          Uri.parse("skinai://routine/daily")
        }
        setOnClickPendingIntent(
          R.id.widget_root,
          HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            rootUri,
          ),
        )
        setOnClickPendingIntent(
          R.id.widget_daily_action,
          HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("skinai://routine/daily"),
          ),
        )
        setOnClickPendingIntent(
          R.id.widget_weekly_action,
          HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("skinai://routine/weekly"),
          ),
        )
        setOnClickPendingIntent(
          R.id.widget_scan_action,
          HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("skinai://scanner"),
          ),
        )
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  private fun firstTask(tasks: JSONArray, fallback: String): String {
    for (index in 0 until tasks.length()) {
      val task = tasks.optJSONObject(index) ?: continue
      val title = task.optString("title", "")
      if (title.isNotBlank()) return title
    }
    return fallback.ifBlank { "Your morning routine is ready" }
  }
}
