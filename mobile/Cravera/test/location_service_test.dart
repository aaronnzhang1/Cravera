import 'dart:async';

import 'package:cravio/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Stands in for the phone's location API, so these tests exercise the real
/// [LocationService] permission checks. It records every attempt to read a
/// position: after a denial there must be none.
class FakeGeolocator extends GeolocatorPlatform {
  FakeGeolocator({
    this.serviceOn = true,
    this.permission = LocationPermission.whileInUse,
    this.afterRequest,
    this.currentError,
    this.cached,
  });

  final bool serviceOn;
  final LocationPermission permission;
  final LocationPermission? afterRequest;
  final Object? currentError;
  final Position? cached;
  int currentReads = 0;
  int cachedReads = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => afterRequest ?? permission;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    currentReads++;
    if (currentError != null) throw currentError!;
    return _position(DateTime.now(), 10);
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async {
    cachedReads++;
    return cached;
  }
}

/// A fictional fix.
Position _position(DateTime at, double accuracy) => Position(
  latitude: 10,
  longitude: 20,
  timestamp: at,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late GeolocatorPlatform original;
  setUp(() => original = GeolocatorPlatform.instance);
  tearDown(() => GeolocatorPlatform.instance = original);

  Future<(LocationResult, FakeGeolocator)> run(FakeGeolocator fake) async {
    GeolocatorPlatform.instance = fake;
    return (await const LocationService().current(), fake);
  }

  test('denied after asking: reports denied and reads no position', () async {
    final (result, fake) = await run(
      FakeGeolocator(permission: LocationPermission.denied, afterRequest: LocationPermission.denied),
    );
    expect(result.problem, LocationProblem.denied);
    expect(fake.currentReads, 0);
    expect(fake.cachedReads, 0);
  });

  test('blocked in settings: reports it and reads no position', () async {
    final (result, fake) = await run(FakeGeolocator(permission: LocationPermission.deniedForever));
    expect(result.problem, LocationProblem.deniedForever);
    expect(fake.currentReads, 0);
    expect(fake.cachedReads, 0);
  });

  test('location off: reports it and reads no position', () async {
    final (result, fake) = await run(FakeGeolocator(serviceOn: false));
    expect(result.problem, LocationProblem.serviceOff);
    expect(fake.currentReads, 0);
    expect(fake.cachedReads, 0);
  });

  test('permission revoked during the fresh read: no fallback to the cached fix', () async {
    final (result, fake) = await run(
      FakeGeolocator(
        currentError: const PermissionDeniedException('revoked'),
        cached: _position(DateTime.now(), 10),
      ),
    );
    expect(result.problem, LocationProblem.failed);
    expect(fake.cachedReads, 0);
  });

  test('a GPS timeout falls back to a fresh, precise cached fix', () async {
    final (result, fake) = await run(
      FakeGeolocator(currentError: TimeoutException('no fix'), cached: _position(DateTime.now(), 50)),
    );
    expect(fake.cachedReads, 1);
    expect(result.location?.label, 'Near you');
  });

  test('a GPS timeout with a stale cached fix asks for a place instead', () async {
    final (result, _) = await run(
      FakeGeolocator(
        currentError: TimeoutException('no fix'),
        cached: _position(DateTime.now().subtract(const Duration(hours: 2)), 50),
      ),
    );
    expect(result.problem, LocationProblem.failed);
  });
}
