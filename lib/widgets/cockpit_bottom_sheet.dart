import 'package:flutter/material.dart';
import '../models/ebike_models.dart';
import '../models/route_models.dart';

class CockpitBottomSheet extends StatelessWidget {
  final double currentSpeedKmh;
  final double currentAltitudeMeters;
  final EbikeProfile profile;
  final EnergyCalculationResult? energyResult;
  final NavigationRoute? activeRoute;
  final VoidCallback onAddChargingPoint;
  final VoidCallback onModeToggle;

  const CockpitBottomSheet({
    super.key,
    required this.currentSpeedKmh,
    required this.currentAltitudeMeters,
    required this.profile,
    required this.energyResult,
    required this.activeRoute,
    required this.onAddChargingPoint,
    required this.onModeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final remainingRangeKm = energyResult?.estimatedRemainingRangeKm ?? 45.0;
    final isDeficit = energyResult != null && !energyResult!.isSufficient;

    // Dinamik Varış Süresi (ETA)
    String etaString = "--:--";
    String remainingDistString = "-- km";
    if (activeRoute != null) {
      final distKm = activeRoute!.totalDistanceKm;
      remainingDistString = "${distKm.toStringAsFixed(1)} km";
      final speedToUse = currentSpeedKmh > 5.0 ? currentSpeedKmh : 20.0;
      final hours = distKm / speedToUse;
      final arrivalTime = DateTime.now().add(Duration(minutes: (hours * 60).round()));
      etaString = "${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}";
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF161D26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, -4),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç Çizgisi
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Kritik Enerji Yetersizliği Uyarı Kartı
          if (isDeficit)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.battery_alert, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Yetersiz Batarya Menzili!",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          "Bu rota için ${energyResult!.deficitWh.toInt()} Wh ek enerji gerekiyor.",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: onAddChargingPoint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red[900],
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    child: const Text("Şarj Noktası Ekle"),
                  ),
                ],
              ),
            ),

          // Ana Telemetri Izgarası
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Hız
              Column(
                children: [
                  RichText(
                    text: TextSpan(
                      text: currentSpeedKmh.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                      children: const [
                        TextSpan(
                          text: " km/s",
                          style: TextStyle(fontSize: 14, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  const Text("HIZ", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),

              // Dikey Ayırıcı
              Container(height: 38, width: 1, color: Colors.white12),

              // 2. Batarya ve Kalan Menzil
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        profile.batteryPercent > 20 ? Icons.battery_charging_full : Icons.battery_alert,
                        color: profile.batteryPercent > 20 ? const Color(0xFF00E676) : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "%${profile.batteryPercent}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    "${remainingRangeKm.toInt()} km menzil",
                    style: const TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),

              // Dikey Ayırıcı
              Container(height: 38, width: 1, color: Colors.white12),

              // 3. Destek Modu
              InkWell(
                onTap: onModeToggle,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BCD4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00BCD4)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        profile.assistMode.displayName,
                        style: const TextStyle(
                          color: Color(0xFF00BCD4),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "MOD",
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),

          // Alt Satır: Rakım, Mesafe ve Varış Saati (ETA)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terrain, color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "${currentAltitudeMeters.toInt()} m Rakım",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.straighten, color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    remainingDistString,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "ETA: $etaString",
                    style: const TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
