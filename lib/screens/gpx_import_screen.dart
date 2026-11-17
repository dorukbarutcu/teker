import 'package:flutter/material.dart';
import '../models/ebike_models.dart';
import '../models/route_models.dart';
import '../services/ebike_calculator.dart';
import '../services/gpx_service.dart';

class GpxImportScreen extends StatefulWidget {
  final EbikeProfile profile;
  final Function(NavigationRoute route) onStartGpxRoute;

  const GpxImportScreen({
    super.key,
    required this.profile,
    required this.onStartGpxRoute,
  });

  @override
  State<GpxImportScreen> createState() => _GpxImportScreenState();
}

class _GpxImportScreenState extends State<GpxImportScreen> {
  NavigationRoute? _parsedRoute;
  EnergyCalculationResult? _energyResult;
  bool _isLoading = false;

  void _pickFile() async {
    setState(() => _isLoading = true);
    final route = await GpxService.pickAndParseGpxFile();

    if (route != null) {
      final energy = EbikeCalculator.calculateRouteEnergy(
        distanceKm: route.totalDistanceKm,
        totalAscentMeters: route.totalAscentMeters,
        profile: widget.profile,
      );
      setState(() {
        _parsedRoute = route;
        _energyResult = energy;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçerli bir GPX rotası seçilemedi.')),
        );
      }
    }
  }

  void _start() {
    if (_parsedRoute != null) {
      widget.onStartGpxRoute(_parsedRoute!);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      appBar: AppBar(
        title: const Text('GPX Parkuru İçe Aktar'),
        backgroundColor: const Color(0xFF161D26),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('Cihazdan .gpx Dosyası Seç'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _isLoading ? null : _pickFile,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
            else if (_parsedRoute != null && _energyResult != null) ...[
              Card(
                color: const Color(0xFF1B2430),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Parkur Analizi', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatItem(label: 'Mesafe', value: '${_parsedRoute!.totalDistanceKm.toStringAsFixed(1)} km'),
                          _StatItem(label: 'Tırmanış', value: '${_parsedRoute!.totalAscentMeters.toInt()} m'),
                          _StatItem(label: 'İniş', value: '${_parsedRoute!.totalDescentMeters.toInt()} m'),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 28),
                      const Text('E-Bike Enerji Analizi', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Gerekli Enerji:', style: TextStyle(color: Colors.white70)),
                          Text('${_energyResult!.requiredEnergyWh.toInt()} Wh', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mevcut Batarya:', style: TextStyle(color: Colors.white70)),
                          Text('${_energyResult!.availableEnergyWh.toInt()} Wh (%${widget.profile.batteryPercent})',
                              style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _energyResult!.isSufficient ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _energyResult!.isSufficient
                              ? '✓ Bataryanız bu parkur için yeterlidir.'
                              : '⚠ Dikkat: Varış için ${_energyResult!.deficitWh.toInt()} Wh ek enerji gerekiyor. Şarj molası planlayın.',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.navigation),
                label: const Text('Bu GPX Parkurunda Navigasyonu Başlat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 54),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                onPressed: _start,
              ),
            ] else ...[
              const Spacer(),
              const Center(
                child: Text(
                  'Harici bisiklet rotalarınızı (.gpx) içe aktararak eğim profili ve batarya menzil simülasyonunu görüntüleyebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38),
                ),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Color(0xFF00BCD4), fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
