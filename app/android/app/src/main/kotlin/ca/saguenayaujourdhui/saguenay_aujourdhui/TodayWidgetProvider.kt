package ca.saguenayaujourdhui.saguenay_aujourdhui

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject

/**
 * Widget « Aujourd'hui ».
 *
 * L'app lui envoie la suite des sept prochains jours, une entrée par
 * changement, et lui demande de se redessiner à chacun d'eux. Le widget prend
 * l'entrée qui correspond à l'heure : pas besoin de réveiller l'app pour que
 * le rappel du soir apparaisse. Passé les sept jours sans que l'app soit
 * ouverte, il le dit plutôt que d'afficher une info périmée.
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // L'heure ou le fuseau change : l'entrée à afficher aussi. Après une mise
        // à jour de l'app, on redessine tout de suite avec la nouvelle version.
        when (intent.action) {
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
                if (ids.isNotEmpty()) render(context, manager, ids, HomeWidgetPlugin.getData(context))
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = render(context, appWidgetManager, appWidgetIds, widgetData)

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        data: SharedPreferences,
    ) {
        val state = State.read(context, data, System.currentTimeMillis())
        ids.forEach { id ->
            val views =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Android choisit lui-même la mise en page selon la taille.
                    RemoteViews(
                        mapOf(
                            SizeF(110f, 40f) to build(context, R.layout.today_widget_small, state),
                            SizeF(200f, 100f) to build(context, R.layout.today_widget, state),
                            SizeF(200f, 230f) to build(context, R.layout.today_widget_large, state),
                        ),
                    )
                } else {
                    build(context, layoutFor(manager.getAppWidgetOptions(id)), state)
                }
            manager.updateAppWidget(id, views)
        }
    }

    private fun layoutFor(options: Bundle): Int {
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 120)
        return when {
            height < 100 -> R.layout.today_widget_small
            height >= 230 -> R.layout.today_widget_large
            else -> R.layout.today_widget
        }
    }

    private fun build(context: Context, layout: Int, s: State): RemoteViews =
        RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.widget_label, s.label)
            setTextViewText(R.id.widget_title, s.title)
            setTextColor(R.id.widget_label, color(context, if (s.critical) "critical" else s.kind))
            setContentDescription(
                R.id.widget_root,
                listOf(s.place, s.label, s.title, s.body).filter { it.isNotEmpty() }.joinToString(". "),
            )
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, s.link),
            )
            if (layout == R.layout.today_widget_small) return@apply

            setTextViewText(R.id.widget_place, s.place)
            setTextViewText(R.id.widget_body, s.body)
            setViewVisibility(R.id.widget_body, if (s.body.isEmpty()) View.GONE else View.VISIBLE)
            // En grande taille, « À venir » prend la place de la deuxième ligne.
            if (s.second != null && layout != R.layout.today_widget_large) {
                setTextViewText(R.id.widget_second, s.second)
                setTextViewText(R.id.widget_second_detail, s.secondDetail.orEmpty())
                setInt(R.id.widget_second_dot, "setColorFilter", color(context, s.secondKind))
                setViewVisibility(R.id.widget_second_row, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_second_row, View.GONE)
            }
            if (layout != R.layout.today_widget_large) return@apply

            val rows =
                listOf(
                    Triple(R.id.widget_next_1, R.id.widget_next_1_when, R.id.widget_next_1_title),
                    Triple(R.id.widget_next_2, R.id.widget_next_2_when, R.id.widget_next_2_title),
                    Triple(R.id.widget_next_3, R.id.widget_next_3_when, R.id.widget_next_3_title),
                )
            setViewVisibility(R.id.widget_next_header, if (s.upcoming.isEmpty()) View.GONE else View.VISIBLE)
            rows.forEachIndexed { i, (row, whenView, titleView) ->
                val next = s.upcoming.getOrNull(i)
                if (next == null) {
                    setViewVisibility(row, View.GONE)
                } else {
                    setTextViewText(whenView, next.first)
                    setTextViewText(titleView, next.second)
                    setViewVisibility(row, View.VISIBLE)
                }
            }
        }

    private fun color(context: Context, kind: String?): Int =
        ContextCompat.getColor(
            context,
            when (kind) {
                "critical" -> R.color.widget_kind_critical
                "water" -> R.color.widget_kind_water
                "weather" -> R.color.widget_kind_weather
                "power" -> R.color.widget_kind_power
                "roads" -> R.color.widget_kind_roads
                "parking" -> R.color.widget_kind_parking
                "collection" -> R.color.widget_kind_collection
                "bus" -> R.color.widget_kind_bus
                "roadwork" -> R.color.widget_kind_roadwork
                else -> R.color.widget_ink_2
            },
        )

    /** Ce que le widget affiche, tiré des données envoyées par l'app. */
    private data class State(
        val place: String,
        val label: String,
        val title: String,
        val body: String = "",
        val kind: String? = null,
        val critical: Boolean = false,
        val second: String? = null,
        val secondDetail: String? = null,
        val secondKind: String? = null,
        val upcoming: List<Pair<String, String>> = emptyList(),
        val link: Uri? = null,
    ) {
        companion object {
            fun read(context: Context, data: SharedPreferences, now: Long): State {
                val place = data.getString("place", null)
                val entries =
                    data.getString("timeline", null)?.let { runCatching { JSONArray(it) }.getOrNull() }
                if (place == null || entries == null || entries.length() == 0) {
                    return State(
                        place = "",
                        label = context.getString(R.string.widget_label_default),
                        title = context.getString(R.string.widget_title_default),
                    )
                }

                val until = data.getString("until", null)?.toLongOrNull()
                if (until != null && now >= until) {
                    return State(
                        place = place,
                        label = context.getString(R.string.widget_stale_label),
                        title = context.getString(R.string.widget_stale_title),
                        body = context.getString(R.string.widget_stale_body),
                    )
                }

                // La dernière entrée déjà commencée, ou la première si l'heure n'y est pas encore.
                var index = 0
                for (i in 0 until entries.length()) {
                    val e = entries.optJSONObject(i) ?: continue
                    if (e.optLong("at") <= now) index = i else break
                }
                val e = entries.optJSONObject(index) ?: JSONObject()
                val kind = e.text("kind")
                return State(
                    place = place,
                    label = e.text("label") ?: context.getString(R.string.widget_label_default),
                    title = e.text("title") ?: context.getString(R.string.widget_title_default),
                    body = e.text("body").orEmpty(),
                    kind = kind,
                    critical = e.optBoolean("critical"),
                    second = e.text("second"),
                    secondDetail = e.text("secondDetail"),
                    secondKind = e.text("secondKind"),
                    upcoming = upcoming(context, entries, index, now, e.text("title")),
                    link = kind?.let { Uri.parse("aujourdhui://detail/$it") },
                )
            }

            /**
             * Les trois prochains changements qui comptent dans les 36 heures. Les
             * départs de bus, qui changent toutes les demi-heures, restent dans
             * la carte principale.
             */
            private fun upcoming(
                context: Context,
                entries: JSONArray,
                index: Int,
                now: Long,
                currentTitle: String?,
            ): List<Pair<String, String>> {
                val out = mutableListOf<Pair<String, String>>()
                val seen = mutableSetOf(currentTitle)
                for (i in index + 1 until entries.length()) {
                    val e = entries.optJSONObject(i) ?: continue
                    val at = e.optLong("at")
                    if (at - now > 36 * 3600_000L) break
                    val kind = e.text("kind") ?: continue
                    val title = e.text("title") ?: continue
                    if (kind == "bus" || !seen.add(title)) continue
                    out += moment(context, at, now) to title
                    if (out.size == 3) break
                }
                return out
            }

            /** « 21 h », « Demain 7 h », « mar. 7 h 46 ». */
            private fun moment(context: Context, at: Long, now: Long): String {
                val t = Calendar.getInstance().apply { timeInMillis = at }
                val today = Calendar.getInstance().apply { timeInMillis = now }
                val hour = t.get(Calendar.HOUR_OF_DAY)
                val minute = t.get(Calendar.MINUTE)
                val clock = if (minute == 0) "$hour h" else "$hour h ${"%02d".format(minute)}"
                val days = daysBetween(today, t)
                val day =
                    when (days) {
                        0 -> ""
                        1 -> context.getString(R.string.widget_tomorrow)
                        else -> shortDays[t.get(Calendar.DAY_OF_WEEK) - 1]
                    }
                // À minuit, le jour suffit : « mar. », pas « mar. 0 h ».
                if (hour == 0 && minute == 0 && day.isNotEmpty()) return day
                return if (day.isEmpty()) clock else "$day $clock"
            }

            /** En jours de calendrier : arrondi, pour tenir compte des changements d'heure. */
            private fun daysBetween(a: Calendar, b: Calendar): Int {
                fun midnight(c: Calendar) =
                    (c.clone() as Calendar)
                        .apply {
                            set(Calendar.HOUR_OF_DAY, 0)
                            set(Calendar.MINUTE, 0)
                            set(Calendar.SECOND, 0)
                            set(Calendar.MILLISECOND, 0)
                        }
                        .timeInMillis
                return Math.round((midnight(b) - midnight(a)) / 86_400_000.0).toInt()
            }

            private val shortDays = listOf("dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam.")

            private fun JSONObject.text(key: String): String? =
                if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
        }
    }
}
