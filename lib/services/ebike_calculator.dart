import '../models/ebike_models.dart';

class EbikeCalculator {
  /// Rota için gereken enerjiyi fizik ve eğim parametreleriyle hesaplar
  static EnergyCalculationResult calculateRouteEnergy({
    required double distanceKm,
    required double totalAscentMeters,
    required EbikeProfile profile,
  }) {
    // 1. Düz yol baz tüketim enerjisi (Wh)
    final double baseDistanceEnergyWh = distanceKm * profile.assistMode.baseWhPerKm;

    // 2. Yokuş/Tırmanış potansiyel enerji tüketimi (Wh)
    // Formül: Tırmanış (m) * Toplam Ağırlık (kg) * 0.00272 * 1.25 (Mekanik ve motor verim faktörü)
    final double climbEnergyWh = totalAscentMeters *
        profile.riderAndBikeWeightKg *
        0.00272 *
        1.25;

    // Toplam Gerekli Enerji
    final double requiredEnergyWh = baseDistanceEnergyWh + climbEnergyWh;

    // Bataryada mevcut enerji
    final double availableEnergyWh = profile.availableEnergyWh;

    // Yeterlilik kontrolü
    final bool isSufficient = availableEnergyWh >= requiredEnergyWh;
    final double deficitWh = isSufficient ? 0.0 : (requiredEnergyWh - availableEnergyWh);

    // Kalan tahmini menzil (düz/ortalama eğim kabulüyle)
    final double estimatedRemainingRangeKm = calculateRemainingRangeKm(
      profile: profile,
      currentSpeedKmh: 20.0,
    );

    return EnergyCalculationResult(
      requiredEnergyWh: requiredEnergyWh,
      availableEnergyWh: availableEnergyWh,
      isSufficient: isSufficient,
      deficitWh: deficitWh,
      estimatedRemainingRangeKm: estimatedRemainingRangeKm,
      climbEnergyWh: climbEnergyWh,
      baseDistanceEnergyWh: baseDistanceEnergyWh,
    );
  }

  /// Anlık hıza, seçili destek moduna ve kalan enerjiye göre dinamik menzil (km)
  static double calculateRemainingRangeKm({
    required EbikeProfile profile,
    double currentSpeedKmh = 20.0,
  }) {
    double baseWhPerKm = profile.assistMode.baseWhPerKm;

    // Aerodinamik sürükleme etkisi: 25 km/s üzerinde rüzgar direnci tüketimi artırır
    if (currentSpeedKmh > 25.0) {
      final speedFactor = 1.0 + ((currentSpeedKmh - 25.0) * 0.03);
      baseWhPerKm *= speedFactor;
    }

    if (baseWhPerKm <= 0.0) return 0.0;
    return profile.availableEnergyWh / baseWhPerKm;
  }
}
