package com.teker.navigation

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session

class TekerCarSession : Session() {

    override fun onCreateScreen(intent: Intent): Screen {
        processIncomingIntent(intent)
        return TekerNavScreen(carContext)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        processIncomingIntent(intent)
    }

    private fun processIncomingIntent(intent: Intent) {
        val action = intent.action ?: return
        val extras = intent.extras
        val data = intent.data

        val params = mutableMapOf<String, Any?>()
        if (data != null) {
            params["data_uri"] = data.toString()
            if (data.scheme == "geo") {
                params["geo_uri"] = data.toString()
            }
            data.queryParameterNames.forEach { name ->
                params[name] = data.getQueryParameter(name)
            }
        }
        if (extras != null) {
            for (key in extras.keySet()) {
                params[key] = extras.get(key)
            }
        }

        val actionType = extras?.getString("action_type")
            ?: data?.getQueryParameter("action_type")
            ?: action

        TekerDataBridge.dispatchAssistantIntent(actionType, params)
    }
}
