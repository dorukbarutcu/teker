package com.teker.navigation

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class TekerCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // Geliştirme, DHU Simülatörü ve Üretim için tüm geçerli hostlara izin ver
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return TekerCarSession()
    }
}
