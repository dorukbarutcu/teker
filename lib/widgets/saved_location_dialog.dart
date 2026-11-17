import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/saved_location_model.dart';
import '../services/gemini_command_service.dart';
import '../services/saved_locations_service.dart';

class SavedLocationDialog extends StatefulWidget {
  final LocationShortcutType defaultType;
  final LatLng currentGpsLocation;
  final SavedLocation? existingLocation;
  final Function(SavedLocation saved) onSaved;

  const SavedLocationDialog({
    super.key,
    required this.defaultType,
    required this.currentGpsLocation,
    this.existingLocation,
    required this.onSaved,
  });

  @override
  State<SavedLocationDialog> createState() => _SavedLocationDialogState();
}

class _SavedLocationDialogState extends State<SavedLocationDialog> {
  late LocationShortcutType _selectedType;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  LatLng? _assignedLocation;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.defaultType;
    if (widget.existingLocation != null) {
      _titleController.text = widget.existingLocation!.title;
      _addressController.text = widget.existingLocation!.address;
      _assignedLocation = widget.existingLocation!.location;
    } else {
      _titleController.text = widget.defaultType.label;
      _assignedLocation = widget.currentGpsLocation;
      _addressController.text = "Anlık Konum (${widget.currentGpsLocation.latitude.toStringAsFixed(4)}, ${widget.currentGpsLocation.longitude.toStringAsFixed(4)})";
    }
  }

  void _searchAddress() async {
    final query = _addressController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    final target = await GeminiCommandService.searchLocationNominatim(query);
    setState(() {
      _isSearching = false;
      if (target != null) {
        _assignedLocation = target;
      }
    });

    if (target != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Konum bulundu: ${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}"),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    }
  }

  void _useCurrentLocation() {
    setState(() {
      _assignedLocation = widget.currentGpsLocation;
      _addressController.text = "Mevcut Konum (${widget.currentGpsLocation.latitude.toStringAsFixed(4)}, ${widget.currentGpsLocation.longitude.toStringAsFixed(4)})";
    });
  }

  void _save() async {
    if (_assignedLocation == null) return;

    final loc = SavedLocation(
      id: _selectedType.id,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : _selectedType.label,
      address: _addressController.text.trim(),
      location: _assignedLocation!,
      iconType: _selectedType.iconName,
    );

    await SavedLocationsService.saveLocation(loc);
    widget.onSaved(loc);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B2430),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF00BCD4),
            child: Icon(
              _getIconForType(_selectedType),
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${_selectedType.label} Konumu Ata",
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kısayol Türü Seçimi
            const Text("Kısayol Türü:", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: LocationShortcutType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Text(type.label),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E676),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedType = type;
                        if (_titleController.text.isEmpty ||
                            LocationShortcutType.values.any((t) => t.label == _titleController.text)) {
                          _titleController.text = type.label;
                        }
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Başlık
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Konum Başlığı",
                labelStyle: const TextStyle(color: Colors.white60),
                filled: true,
                fillColor: const Color(0xFF263238),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 12),

            // Adres veya Arama
            TextField(
              controller: _addressController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Adres veya Yer Adı",
                labelStyle: const TextStyle(color: Colors.white60),
                filled: true,
                fillColor: const Color(0xFF263238),
                suffixIcon: IconButton(
                  icon: _isSearching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, color: Color(0xFF00BCD4)),
                  onPressed: _isSearching ? null : _searchAddress,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _searchAddress(),
            ),

            const SizedBox(height: 12),

            // Anlık Konumu Ata Butonu
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location, color: Color(0xFF00E676)),
              label: const Text("Anlık GPS Konumumu Buraya Ata", style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF00E676)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _useCurrentLocation,
            ),

            if (_assignedLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Koordinat: ${_assignedLocation!.latitude.toStringAsFixed(5)}, ${_assignedLocation!.longitude.toStringAsFixed(5)}",
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("İptal", style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _save,
          child: const Text("Kaydet", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  IconData _getIconForType(LocationShortcutType type) {
    switch (type) {
      case LocationShortcutType.home:
        return Icons.home;
      case LocationShortcutType.school:
        return Icons.school;
      case LocationShortcutType.work:
        return Icons.work;
      case LocationShortcutType.favorite:
        return Icons.star;
    }
  }
}
