enum EbikeAssistMode {
  eco(displayName: 'Eco', baseWhPerKm: 8.0),
  tour(displayName: 'Tour', baseWhPerKm: 12.0),
  sport(displayName: 'Sport', baseWhPerKm: 16.0),
  turbo(displayName: 'Turbo', baseWhPerKm: 22.0);

  final String displayName;
  final double baseWhPerKm;

  const EbikeAssistMode({
    required this.displayName,
    required this.baseWhPerKm,
  });

  static EbikeAssistMode fromString(String name) {
    switch (name.toLowerCase()) {
      case 'eco':
        return EbikeAssistMode.eco;
      case 'tour':
        return EbikeAssistMode.tour;
      case 'sport':
        return EbikeAssistMode.sport;
      case 'turbo':
        return EbikeAssistMode.turbo;
      default:
        return EbikeAssistMode.tour;
    }
  }
}

class EbikeProfile {
  double batteryCapacityWh;
  double voltage;
  double ampHours;
  int batteryPercent; // 0 - 100
  EbikeAssistMode assistMode;
  double riderAndBikeWeightKg;

  EbikeProfile({
    this.batteryCapacityWh = 504.0, // 36V x 14Ah
    this.voltage = 36.0,
    this.ampHours = 14.0,
    this.batteryPercent = 85,
    this.assistMode = EbikeAssistMode.tour,
    this.riderAndBikeWeightKg = 95.0, // 75kg sürücü + 20kg bisiklet
  });

  double get availableEnergyWh => batteryCapacityWh * (batteryPercent / 100.0);

  void updateByVoltageAndAh(double v, double ah) {
    voltage = v;
    ampHours = ah;
    batteryCapacityWh = v * ah;
  }
}

class EnergyCalculationResult {
  final double requiredEnergyWh;
  final double availableEnergyWh;
  final bool isSufficient;
  final double deficitWh;
  final double estimatedRemainingRangeKm;
  final double climbEnergyWh;
  final double baseDistanceEnergyWh;

  EnergyCalculationResult({
    required this.requiredEnergyWh,
    required this.availableEnergyWh,
    required this.isSufficient,
    required this.deficitWh,
    required this.estimatedRemainingRangeKm,
    required this.climbEnergyWh,
    required this.baseDistanceEnergyWh,
  });
}
