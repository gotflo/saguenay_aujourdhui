import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/colors.dart';

/// Faux dans les tests : pas de tuiles à télécharger.
final mapTilesProvider = Provider<bool>((ref) => true);

/// Une zone à colorier sur la carte : un avis d'eau, par exemple.
typedef MapZone = ({List<List<LonLat>> rings, Color color});

/// Une petite carte, telle que la Ville la dessine en ce moment : les zones
/// des avis, les tracés des chantiers et l'adresse. On zoome du bout des
/// doigts ; on ne la fait pas glisser, pour ne pas gêner le défilement.
class LiveMap extends ConsumerWidget {
  const LiveMap({
    super.key,
    required this.lat,
    required this.lon,
    this.zones = const [],
    this.paths = const [],
    this.height = 200,
    this.semanticLabel,
  });

  final double lat;
  final double lon;
  final List<MapZone> zones;
  final List<List<LonLat>> paths;
  final double height;

  /// Ce que la carte montre, pour un lecteur d'écran.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final home = LatLng(lat, lon);
    LatLng point(LonLat p) => LatLng(p.$2, p.$1);
    final shown = [
      home,
      for (final z in zones)
        for (final ring in z.rings) ...ring.map(point),
      for (final path in paths) ...path.map(point),
    ];

    return Semantics(
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: home,
              initialZoom: 14,
              initialCameraFit: shown.length < 2
                  ? null
                  : CameraFit.coordinates(
                      coordinates: shown,
                      padding: const EdgeInsets.all(28),
                      maxZoom: 16,
                    ),
              backgroundColor: c.bg,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              if (ref.watch(mapTilesProvider))
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ca.saguenayaujourdhui.saguenay_aujourdhui',
                  tileBuilder: dark ? darkModeTileBuilder : null,
                ),
              PolygonLayer(
                polygons: [
                  for (final z in zones)
                    for (final ring in z.rings)
                      Polygon(
                        points: ring.map(point).toList(),
                        color: z.color.withValues(alpha: .22),
                        borderColor: z.color,
                        borderStrokeWidth: 2,
                      ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  for (final path in paths)
                    Polyline(points: path.map(point).toList(), color: c.orange, strokeWidth: 5),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: home,
                    width: 22,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.accent, width: 4),
                      ),
                    ),
                  ),
                ],
              ),
              // L'attribution exigée par OpenStreetMap, discrète mais lisible.
              Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.card.withValues(alpha: .85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '© OpenStreetMap',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.ink2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
