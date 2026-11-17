import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ebike_models.dart';

class EbikeSettingsScreen extends StatefulWidget {
  final EbikeProfile profile;
  final Function(EbikeProfile updated) onSave;

  const EbikeSettingsScreen({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<EbikeSettingsScreen> createState() => _EbikeSettingsScreenState();
}

class _EbikeSettingsScreenState extends State<EbikeSettingsScreen> {
  late double _capacityWh;
  late double _voltage;
  late double _ampHours;
  late int _batteryPercent;
  late double _weightKg;
  late EbikeAssistMode _assistMode;

  @override
  void initState() {
    super.initState();
    _capacityWh = widget.profile.batteryCapacityWh;
    _voltage = widget.profile.voltage;
    _ampHours = widget.profile.ampHours;
    _batteryPercent = widget.profile.batteryPercent;
    _weightKg = widget.profile.riderAndBikeWeightKg;
    _assistMode = widget.profile.assistMode;
  }

  void _recalcWh() {
    setState(() {
      _capacityWh = _voltage * _ampHours;
    });
  }

  void _save() async {
    final updated = EbikeProfile(
      batteryCapacityWh: _capacityWh,
      voltage: _voltage,
      ampHours: _ampHours,
      batteryPercent: _batteryPercent,
      assistMode: _assistMode,
      riderAndBikeWeightKg: _weightKg,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ebike_capacity', _capacityWh);
    await prefs.setDouble('ebike_voltage', _voltage);
    await prefs.setDouble('ebike_ah', _ampHours);
    await prefs.setInt('ebike_battery_pct', _batteryPercent);
    await prefs.setDouble('ebike_weight', _weightKg);
    await prefs.setString('ebike_mode', _assistMode.name);

    widget.onSave(updated);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      appBar: AppBar(
        title: const Text('E-Bike Batarya & Profil'),
        backgroundColor: const Color(0xFF161D26),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF00E676)),
            onPressed: _save,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Kapasite Kartı
          Card(
            color: const Color(0xFF1B2430),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Batarya Kapasitesi',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_capacityWh.toInt()} Wh',
                        style: const TextStyle(color: Color(0xFF00BCD4), fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Voltaj (V): ${_voltage.toInt()}V', style: const TextStyle(color: Colors.white70)),
                            Slider(
                              value: _voltage,
                              min: 24,
                              max: 52,
                              divisions: 7,
                              activeColor: const Color(0xFF00BCD4),
                              onChanged: (v) {
                                _voltage = v;
                                _recalcWh();
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kapasite (Ah): ${_ampHours.toStringAsFixed(1)}Ah', style: const TextStyle(color: Colors.white70)),
                            Slider(
                              value: _ampHours,
                              min: 5,
                              max: 30,
                              divisions: 25,
                              activeColor: const Color(0xFF00BCD4),
                              onChanged: (ah) {
                                _ampHours = ah;
                                _recalcWh();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Anlık Batarya Yüzdesi
          Card(
            color: const Color(0xFF1B2430),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mevcut Şarj Yüzdesi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('%$_batteryPercent', style: const TextStyle(color: Color(0xFF00E676), fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _batteryPercent.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: const Color(0xFF00E676),
                    onChanged: (val) {
                      setState(() {
                        _batteryPercent = val.round();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Destek Modu Seçimi
          Card(
            color: const Color(0xFF1B2430),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Varsayılan Destek Modu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: EbikeAssistMode.values.map((mode) {
                      final isSelected = _assistMode == mode;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _assistMode = mode),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF00BCD4) : const Color(0xFF263238),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Text(
                                  mode.displayName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${mode.baseWhPerKm.toInt()} Wh/km',
                                  style: TextStyle(
                                    color: isSelected ? Colors.black87 : Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Toplam Ağırlık (Sürücü + Bisiklet + Çanta)
          Card(
            color: const Color(0xFF1B2430),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sürücü + Bisiklet Ağırlığı', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${_weightKg.toInt()} kg', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _weightKg,
                    min: 40,
                    max: 160,
                    divisions: 24,
                    activeColor: const Color(0xFFFFB300),
                    onChanged: (w) => setState(() => _weightKg = w),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
