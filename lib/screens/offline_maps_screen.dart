import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/offline_map_manager.dart';

class OfflineMapsScreen extends StatefulWidget {
  final Function(LatLng center, double zoom)? onFocusRegion;

  const OfflineMapsScreen({super.key, this.onFocusRegion});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  BoundarySearchResult? _searchResult;
  String _detailLevel = 'city'; // 'city' (10-16) veya 'region' (7-13)

  int _estTiles = 0;
  double _estMb = 0.0;

  // İndirme Durumu
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedCount = 0;
  int _totalCount = 0;

  List<DownloadedRegion> _savedRegions = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  void _loadSaved() async {
    final list = await OfflineMapManager.getSavedRegions();
    setState(() {
      _savedRegions = list;
    });
  }

  void _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResult = null;
    });

    final res = await OfflineMapManager.searchAdministrativeBoundary(query);
    setState(() {
      _isSearching = false;
      _searchResult = res;
    });

    if (res != null) {
      _calculateEstimate();
    }
  }

  void _calculateEstimate() {
    if (_searchResult == null) return;

    final minZoom = _detailLevel == 'city' ? 10 : 7;
    final maxZoom = _detailLevel == 'city' ? 16 : 13;

    final estimate = OfflineMapManager.estimateTilesAndSize(
      minLat: _searchResult!.minLat,
      maxLat: _searchResult!.maxLat,
      minLon: _searchResult!.minLon,
      maxLon: _searchResult!.maxLon,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    setState(() {
      _estTiles = estimate['totalTiles'];
      _estMb = estimate['estimatedMb'];
    });
  }

  void _startDownload() async {
    if (_searchResult == null) return;

    final minZoom = _detailLevel == 'city' ? 10 : 7;
    final maxZoom = _detailLevel == 'city' ? 16 : 13;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedCount = 0;
      _totalCount = _estTiles;
    });

    await OfflineMapManager.downloadRegionTiles(
      regionName: _searchController.text.trim(),
      detailLevel: _detailLevel,
      minLat: _searchResult!.minLat,
      maxLat: _searchResult!.maxLat,
      minLon: _searchResult!.minLon,
      maxLon: _searchResult!.maxLon,
      minZoom: minZoom,
      maxZoom: maxZoom,
      onProgress: (progress, downloaded, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadedCount = downloaded;
            _totalCount = total;
          });
        }
      },
    );

    setState(() {
      _isDownloading = false;
    });
    _loadSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      appBar: AppBar(
        title: const Text('Çevrimdışı Harita Yöneticisi'),
        backgroundColor: const Color(0xFF161D26),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Arama Çubuğu
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ülke, bölge veya şehir ara (Örn: Mersin)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1B2430),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearching ? null : _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Bul', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Arama Sonucu ve İndirme Öncesi Tahmin Paneli
          if (_searchResult != null) ...[
            Card(
              color: const Color(0xFF1B2430),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map, color: Color(0xFF00BCD4)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _searchResult!.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Text('Detay Seviyesi Seçin:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Şehir İçi (Zoom 10-16)'),
                          selected: _detailLevel == 'city',
                          selectedColor: const Color(0xFF00BCD4),
                          onSelected: (val) {
                            if (val) {
                              setState(() => _detailLevel = 'city');
                              _calculateEstimate();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Bölgesel (Zoom 7-13)'),
                          selected: _detailLevel == 'region',
                          selectedColor: const Color(0xFF00BCD4),
                          onSelected: (val) {
                            if (val) {
                              setState(() => _detailLevel = 'region');
                              _calculateEstimate();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF263238),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('$_estTiles', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            const Text('Karo Sayısı', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('$_estMb MB', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
                            const Text('Tahmini Boyut', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isDownloading)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Bu Bölgeyi Çevrimdışı İndir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _startDownload,
                      ),
                    )
                  else ...[
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF00E676),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '%${(_downloadProgress * 100).toInt()} ($_downloadedCount / $_totalCount)',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(OfflineMapManager.isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  OfflineMapManager.isPaused = !OfflineMapManager.isPaused;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  OfflineMapManager.isCancelled = true;
                                  _isDownloading = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

          // İndirilen Haritalar Listesi
          const Text(
            'İndirilen Çevrimdışı Haritalar',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (_savedRegions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Henüz indirilmiş çevrimdışı harita bulunmuyor.\nYukarıdan bir şehir arayıp indirebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            ..._savedRegions.map((region) {
              return Card(
                color: const Color(0xFF1B2430),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF00BCD4),
                    child: Icon(Icons.offline_pin, color: Colors.black),
                  ),
                  title: Text(
                    region.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${region.sizeMb} MB • ${region.totalTiles} karo • Zoom ${region.minZoom}-${region.maxZoom}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.my_location, color: Color(0xFF00E676)),
                        onPressed: () {
                          final center = LatLng(
                            (region.minLat + region.maxLat) / 2.0,
                            (region.minLon + region.maxLon) / 2.0,
                          );
                          widget.onFocusRegion?.call(center, 13.0);
                          Navigator.pop(context);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await OfflineMapManager.deleteRegion(region);
                          _loadSaved();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
