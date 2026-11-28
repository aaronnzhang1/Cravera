import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/saved_hub.dart';
import '../services/saved_places_service.dart';

/// Whether this build can show a Google map (ADR 0006). Android reads its
/// restricted key from local.properties at build time; iOS needs its key in
/// the git-ignored MapsKey.xcconfig and `--dart-define=IOS_MAPS=true`, since
/// the SDK crashes without one. Web isn't a target.
bool get mapsAvailable {
  if (kIsWeb) return false;
  if (Platform.isAndroid) return true;
  if (Platform.isIOS) return const bool.fromEnvironment('IOS_MAPS');
  return false;
}

/// A real Google map (Maps SDK) with a pin for each saved place in [places]
/// that has a fresh location. Locations are never stored: they come from this
/// visit's `saved-places` answer. Tapping a pin calls [onOpen].
class SavedMap extends StatelessWidget {
  final List<SavedPlace> places;
  final SavedHub hub;
  final ValueChanged<SavedPlace> onOpen;
  const SavedMap({super.key, required this.places, required this.hub, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final pinned = [
      for (final p in places)
        if (hub.basics(p.placeId) case final b? when b.latitude != null && b.longitude != null) (p, b),
    ];
    if (pinned.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No places to show on the map yet.')),
      );
    }
    final points = [for (final (_, b) in pinned) LatLng(b.latitude!, b.longitude!)];
    final camera = CameraPosition(target: _centre(points), zoom: 12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 420,
        child: GoogleMap(
          initialCameraPosition: camera,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          // Street View is billed; it stays off (ADR 0006).
          markers: {
            for (final (p, b) in pinned)
              Marker(
                markerId: MarkerId(p.placeId),
                position: LatLng(b.latitude!, b.longitude!),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  p.status == SavedStatus.been ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
                ),
                infoWindow: InfoWindow(title: b.name, snippet: 'Tap for details', onTap: () => onOpen(p)),
              ),
          },
          onMapCreated: (controller) {
            if (points.length > 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                controller.animateCamera(CameraUpdate.newLatLngBounds(_bounds(points), 48));
              });
            }
          },
        ),
      ),
    );
  }

  static LatLng _centre(List<LatLng> points) {
    final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(lat, lng);
  }

  static LatLngBounds _bounds(List<LatLng> points) {
    var s = points.first.latitude, n = s, w = points.first.longitude, e = w;
    for (final p in points) {
      s = p.latitude < s ? p.latitude : s;
      n = p.latitude > n ? p.latitude : n;
      w = p.longitude < w ? p.longitude : w;
      e = p.longitude > e ? p.longitude : e;
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }
}
