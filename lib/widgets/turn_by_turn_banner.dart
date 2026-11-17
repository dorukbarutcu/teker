import 'package:flutter/material.dart';
import '../models/route_models.dart';

class TurnByTurnBanner extends StatelessWidget {
  final ManeuverStep? maneuver;

  const TurnByTurnBanner({
    super.key,
    required this.maneuver,
  });

  @override
  Widget build(BuildContext context) {
    if (maneuver == null) return const SizedBox.shrink();

    IconData getTurnIcon(int type) {
      switch (type) {
        case 2:
          return Icons.turn_left;
        case 3:
          return Icons.turn_right;
        case 4:
          return Icons.roundabout_right;
        default:
          return Icons.straight;
      }
    }

    final distText = maneuver!.distanceMeters > 1000
        ? '${(maneuver!.distanceMeters / 1000.0).toStringAsFixed(1)} km'
        : '${maneuver!.distanceMeters.toInt()} m';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2430),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
        border: Border.all(color: const Color(0xFF00E676), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF00E676),
            child: Icon(
              getTurnIcon(maneuver!.type),
              color: Colors.black,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distText,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  maneuver!.instruction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (maneuver!.streetName.isNotEmpty)
                  Text(
                    maneuver!.streetName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
