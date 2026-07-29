package com.aivideomaker.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.app.PendingIntent
import android.net.Uri
import android.widget.RemoteViews
import android.view.View
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import com.aivideomaker.app.R

class DailyProgressWidgetProvider : HomeWidgetProvider() {

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, DailyProgressWidgetProvider::class.java))
        if (ids != null && ids.isNotEmpty()) {
            updateFromFallback(context, manager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_daily_progress)

            val fallback = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            var goalCal = widgetData.getInt("dp_goal_cal", fallback.getInt("dp_goal_cal", 0))
            var goalP = widgetData.getInt("dp_goal_protein", fallback.getInt("dp_goal_protein", 0))
            var goalF = widgetData.getInt("dp_goal_fat", fallback.getInt("dp_goal_fat", 0))
            var goalC = widgetData.getInt("dp_goal_carbs", fallback.getInt("dp_goal_carbs", 0))
            var waterGoal = widgetData.getInt("water_goal_ml", fallback.getInt("water_goal_ml", 0))

            if (goalCal == 0 || goalP == 0 || goalF == 0 || goalC == 0 || waterGoal == 0) {
                val userJson = fallback.getString("flutter.user_data", null)
                if (!userJson.isNullOrEmpty()) {
                    try {
                        val user = JSONObject(userJson)
                        val goals = user.optJSONObject("nutritionGoals")
                        if (goals != null) {
                            if (goalCal == 0) goalCal = goals.optInt("dailyCalories", goalCal)
                            if (goalP == 0) goalP = goals.optInt("dailyProtein", goalP)
                            if (goalF == 0) goalF = goals.optInt("dailyFat", goalF)
                            if (goalC == 0) goalC = goals.optInt("dailyCarbs", goalC)
                            if (waterGoal == 0) waterGoal = goals.optInt("dailyWaterMl", waterGoal)
                        }
                    } catch (_: Exception) { }
                }
            }

            val cal = widgetData.getInt("dp_cal", fallback.getInt("dp_cal", 0))
            val p = widgetData.getInt("dp_protein", fallback.getInt("dp_protein", 0))
            val f = widgetData.getInt("dp_fat", fallback.getInt("dp_fat", 0))
            val c = widgetData.getInt("dp_carbs", fallback.getInt("dp_carbs", 0))
            val water = widgetData.getInt("water_total_ml", fallback.getInt("water_total_ml", 0))
            val date = widgetData.getString("dp_date", "Сегодня")

            views.setTextViewText(R.id.dp_date, if (date == "Сегодня") "Сегодня" else date)

            val calRemain = (goalCal - cal).coerceAtLeast(0)
            views.setTextViewText(R.id.dp_cal_value, formatPair(calRemain, goalCal, "ккал"))
            val calPct = if (goalCal > 0) (cal * 100 / goalCal).coerceIn(0, 100) else 0
            views.setTextViewText(R.id.dp_cal_inside, "$cal ккал")
            views.setProgressBar(R.id.dp_cal_progress, 100, calPct, false)

            views.setTextViewText(R.id.dp_p_value, formatPair((goalP - p).coerceAtLeast(0), goalP, "г"))
            val pPct = if (goalP > 0) (p * 100 / goalP).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_p_progress, 100, pPct, false)
            views.setTextViewText(R.id.dp_p_inside, "${p} г")

            views.setTextViewText(R.id.dp_f_value, formatPair((goalF - f).coerceAtLeast(0), goalF, "г"))
            val fPct = if (goalF > 0) (f * 100 / goalF).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_f_progress, 100, fPct, false)
            views.setTextViewText(R.id.dp_f_inside, "${f} г")

            views.setTextViewText(R.id.dp_c_value, formatPair((goalC - c).coerceAtLeast(0), goalC, "г"))
            val cPct = if (goalC > 0) (c * 100 / goalC).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_c_progress, 100, cPct, false)
            views.setTextViewText(R.id.dp_c_inside, "${c} г")

            views.setTextViewText(R.id.dp_water_value, formatPair((waterGoal - water).coerceAtLeast(0), waterGoal, "мл"))
            val wPct = if (waterGoal > 0) (water * 100 / waterGoal).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_water_progress, 100, wPct, false)
            views.setTextViewText(R.id.dp_water_inside, "${water} мл")

            val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val isTwoRows = isTwoRowLayout(options)

            val voiceIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                addCategory(Intent.CATEGORY_BROWSABLE)
                data = Uri.parse("aivideomaker://action/add_food_voice")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val voicePI = PendingIntent.getActivity(context, 1001, voiceIntent, flags or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.btn_voice, voicePI)

            val photoIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                addCategory(Intent.CATEGORY_BROWSABLE)
                data = Uri.parse("aivideomaker://action/add_food_photo")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val photoPI = PendingIntent.getActivity(context, 1002, photoIntent, flags or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.btn_photo, photoPI)

            val waterIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                addCategory(Intent.CATEGORY_BROWSABLE)
                data = Uri.parse("aivideomaker://action/add_water")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val waterPI = PendingIntent.getActivity(context, 1003, waterIntent, flags or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.btn_water, waterPI)

            val textIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                addCategory(Intent.CATEGORY_BROWSABLE)
                data = Uri.parse("aivideomaker://action/add_food_text")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val textPI = PendingIntent.getActivity(context, 1004, textIntent, flags or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.btn_text, textPI)

            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val openAppPI = PendingIntent.getActivity(context, 1000, openAppIntent, flags or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.dp_root, openAppPI)

            applyCompactMode(views, isTwoRows)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val views = RemoteViews(context.packageName, R.layout.widget_daily_progress)
        val isTwoRows = isTwoRowLayout(newOptions)
        applyCompactMode(views, isTwoRows)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun isTwoRowLayout(options: Bundle?): Boolean {
        if (options == null) return false
        val heights = listOf(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        ).filter { it > 0 }
        if (heights.isEmpty()) return false
        val rowsCandidates = heights.map { h -> Math.ceil(((h + 30).toDouble()) / 70.0).toInt() }
        val rows = rowsCandidates.minOrNull() ?: 3
        return rows < 3
    }

    private fun applyCompactMode(views: RemoteViews, isTwoRows: Boolean) {
        val visibility = if (isTwoRows) View.GONE else View.VISIBLE
        views.setViewVisibility(R.id.action_buttons, visibility)
        views.setViewVisibility(R.id.row_water, visibility)
        views.setViewVisibility(R.id.dp_water_label, visibility)
        views.setViewVisibility(R.id.dp_water_value, visibility)
        views.setViewVisibility(R.id.dp_water_progress, visibility)
        views.setViewVisibility(R.id.dp_water_inside, visibility)
        if (isTwoRows) {
            views.setTextViewText(R.id.dp_water_label, "")
            views.setTextViewText(R.id.dp_water_value, "")
            views.setTextViewText(R.id.dp_water_inside, "")
            views.setProgressBar(R.id.dp_water_progress, 100, 0, false)
        }
    }

    private fun formatPair(value: Int, goal: Int, unit: String): String {
        return "$value / $goal $unit"
    }

    private fun updateFromFallback(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val fallback = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        var goalCal = fallback.getInt("dp_goal_cal", 0)
        var goalP = fallback.getInt("dp_goal_protein", 0)
        var goalF = fallback.getInt("dp_goal_fat", 0)
        var goalC = fallback.getInt("dp_goal_carbs", 0)
        var waterGoal = fallback.getInt("water_goal_ml", 0)

        if (goalCal == 0 || goalP == 0 || goalF == 0 || goalC == 0 || waterGoal == 0) {
            val userJson = fallback.getString("flutter.user_data", null)
            if (!userJson.isNullOrEmpty()) {
                try {
                    val user = JSONObject(userJson)
                    val goals = user.optJSONObject("nutritionGoals")
                    if (goals != null) {
                        if (goalCal == 0) goalCal = goals.optInt("dailyCalories", goalCal)
                        if (goalP == 0) goalP = goals.optInt("dailyProtein", goalP)
                        if (goalF == 0) goalF = goals.optInt("dailyFat", goalF)
                        if (goalC == 0) goalC = goals.optInt("dailyCarbs", goalC)
                        if (waterGoal == 0) waterGoal = goals.optInt("dailyWaterMl", waterGoal)
                    }
                } catch (_: Exception) { }
            }
        }

        val cal = fallback.getInt("dp_cal", 0)
        val p = fallback.getInt("dp_protein", 0)
        val f = fallback.getInt("dp_fat", 0)
        val c = fallback.getInt("dp_carbs", 0)
        val water = fallback.getInt("water_total_ml", 0)
        val date = fallback.getString("dp_date", "Сегодня")

        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_daily_progress)
            views.setTextViewText(R.id.dp_date, if (date == "Сегодня") "Сегодня" else date)

            val calRemain = (goalCal - cal).coerceAtLeast(0)
            views.setTextViewText(R.id.dp_cal_value, formatPair(calRemain, goalCal, "ккал"))
            val calPct = if (goalCal > 0) (cal * 100 / goalCal).coerceIn(0, 100) else 0
            views.setTextViewText(R.id.dp_cal_inside, "$cal ккал")
            views.setProgressBar(R.id.dp_cal_progress, 100, calPct, false)

            views.setTextViewText(R.id.dp_p_value, formatPair((goalP - p).coerceAtLeast(0), goalP, "г"))
            val pPct = if (goalP > 0) (p * 100 / goalP).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_p_progress, 100, pPct, false)
            views.setTextViewText(R.id.dp_p_inside, "${p} г")

            views.setTextViewText(R.id.dp_f_value, formatPair((goalF - f).coerceAtLeast(0), goalF, "г"))
            val fPct = if (goalF > 0) (f * 100 / goalF).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_f_progress, 100, fPct, false)
            views.setTextViewText(R.id.dp_f_inside, "${f} г")

            views.setTextViewText(R.id.dp_c_value, formatPair((goalC - c).coerceAtLeast(0), goalC, "г"))
            val cPct = if (goalC > 0) (c * 100 / goalC).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_c_progress, 100, cPct, false)
            views.setTextViewText(R.id.dp_c_inside, "${c} г")

            views.setTextViewText(R.id.dp_water_value, formatPair((waterGoal - water).coerceAtLeast(0), waterGoal, "мл"))
            val wPct = if (waterGoal > 0) (water * 100 / waterGoal).coerceIn(0, 100) else 0
            views.setProgressBar(R.id.dp_water_progress, 100, wPct, false)
            views.setTextViewText(R.id.dp_water_inside, "${water} мл")

            val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

            val voiceIntent = Intent(Intent.ACTION_VIEW, Uri.parse("aivideomaker://action/add_food_voice"), context, MainActivity::class.java)
            val voicePI = PendingIntent.getActivity(context, 1001, voiceIntent, flags)
            views.setOnClickPendingIntent(R.id.btn_voice, voicePI)

            val photoIntent = Intent(Intent.ACTION_VIEW, Uri.parse("aivideomaker://action/add_food_photo"), context, MainActivity::class.java)
            val photoPI = PendingIntent.getActivity(context, 1002, photoIntent, flags)
            views.setOnClickPendingIntent(R.id.btn_photo, photoPI)

            val waterIntent = Intent(Intent.ACTION_VIEW, Uri.parse("aivideomaker://action/add_water"), context, MainActivity::class.java)
            val waterPI = PendingIntent.getActivity(context, 1003, waterIntent, flags)
            views.setOnClickPendingIntent(R.id.btn_water, waterPI)

            val openAppIntent = Intent(context, MainActivity::class.java)
            val openAppPI = PendingIntent.getActivity(context, 1000, openAppIntent, flags)
            views.setOnClickPendingIntent(R.id.dp_root, openAppPI)

            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val isTwoRows = isTwoRowLayout(options)
            applyCompactMode(views, isTwoRows)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
