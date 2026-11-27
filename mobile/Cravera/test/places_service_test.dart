import 'dart:async';
import 'dart:convert';

import 'package:cravera/core/constants.dart';
import 'package:cravera/services/location_service.dart';
import 'package:cravera/services/places_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Fictional data only. The network is faked with MockClient.

const near = SearchLocation(latitude: 37.0, longitude: -122.0, label: 'Near you');

Map<String, Object?> result({String placeId = 'fake-1', Map<String, Object?> overrides = const {}}) => {
      'placeId': placeId,
      'name': 'Test Noodle House',
      'address': '1 Example St, Testville',
      'cuisine': 'Ramen Restaurant',
      'priceLevel': 2,
      'rating': 4.4,
      'distanceMeters': 150,
      'photoName': 'places/$placeId/photos/abc',
      'latitude': 37.001,
      'longitude': -122.001,
      ...overrides,
    };

PlacesService serviceWith(MockClient client, {Duration timeout = PlacesService.defaultTimeout}) => PlacesService(
      publishableKey: 'sb_publishable_test',
      client: client,
      timeout: timeout,
    );

Future<PlacesSearchError?> errorFor(MockClient client) async {
  try {
    await serviceWith(client).search(query: 'ramen', near: near);
    return null;
  } on PlacesSearchException catch (e) {
    return e.error;
  }
}

void main() {
  group('request', () {
    test('posts the query and location to the function with the publishable key', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'results': []}), 200);
      });
      await serviceWith(client).search(query: 'ramen', near: near, radiusMeters: 3000);

      expect(sent.method, 'POST');
      expect(sent.url, PlacesService.endpoint);
      expect(sent.headers['apikey'], 'sb_publishable_test');
      expect(jsonDecode(sent.body), {'query': 'ramen', 'latitude': 37.0, 'longitude': -122.0, 'radiusMeters': 3000});
    });

    test('leaves the radius out when none is given, so the server default applies', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'results': []}), 200);
      });
      await serviceWith(client).search(query: 'ramen', near: near);
      expect((jsonDecode(sent.body) as Map).containsKey('radiusMeters'), isFalse);
    });
  });

  group('parsing', () {
    test('maps every field from the response', () {
      final [r] = PlacesService.parseResults(jsonEncode({'results': [result()]}));
      expect(r.placeId, 'fake-1');
      expect(r.name, 'Test Noodle House');
      expect(r.address, '1 Example St, Testville');
      expect(r.cuisine, 'Ramen Restaurant');
      expect(r.priceLevel, 2);
      expect(r.rating, 4.4);
      expect(r.distanceMeters, 150);
      expect(r.photoName, 'places/fake-1/photos/abc');
      expect(r.latitude, 37.001);
      expect(r.longitude, -122.001);
      expect(r.photoUrl, isNull);
    });

    test('keeps the server order', () {
      final list = PlacesService.parseResults(jsonEncode({
        'results': [result(placeId: 'b'), result(placeId: 'a'), result(placeId: 'c')],
      }));
      expect(list.map((r) => r.placeId), ['b', 'a', 'c']);
    });

    test('missing optional fields stay null, never demo data', () {
      final [r] = PlacesService.parseResults(jsonEncode({
        'results': [
          result(overrides: {'address': null, 'cuisine': null, 'priceLevel': null, 'rating': null, 'photoName': null}),
        ],
      }));
      expect([r.address, r.cuisine, r.priceLevel, r.rating, r.photoName], everyElement(isNull));
    });

    test('skips entries without an ID, name or location', () {
      final list = PlacesService.parseResults(jsonEncode({
        'results': [
          result(placeId: 'no-name', overrides: {'name': ''}),
          result(placeId: 'no-lat', overrides: {'latitude': null}),
          result(overrides: {'placeId': null}),
          result(placeId: 'bad-lat', overrides: {'latitude': 91}),
          result(placeId: 'bad-lng', overrides: {'longitude': -181}),
          'not an object',
          result(placeId: 'ok'),
        ],
      }));
      expect(list.map((r) => r.placeId), ['ok']);
    });

    test('a list where every row is broken is a server error, not "no matches"', () {
      expect(
        () => PlacesService.parseResults(jsonEncode({
          'results': [result(overrides: {'name': null}), result(overrides: {'latitude': 200})],
        })),
        throwsA(isA<PlacesSearchException>().having((e) => e.error, 'error', PlacesSearchError.server)),
      );
    });

    test('accepts whole numbers where decimals are expected', () {
      final [r] = PlacesService.parseResults(jsonEncode({
        'results': [result(overrides: {'rating': 4, 'latitude': 37, 'distanceMeters': 150.6})],
      }));
      expect(r.rating, 4.0);
      expect(r.latitude, 37.0);
      expect(r.distanceMeters, 151);
    });

    test('an empty result list is not an error', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'results': []}), 200));
      expect(await serviceWith(client).search(query: 'ramen', near: near), isEmpty);
    });

    test('a malformed body is a server error', () async {
      expect(await errorFor(MockClient((_) async => http.Response('not json', 200))), PlacesSearchError.server);
      expect(await errorFor(MockClient((_) async => http.Response('{"oops":1}', 200))), PlacesSearchError.server);
    });
  });

  group('failures', () {
    test('maps status codes to errors the screen can explain', () async {
      Future<PlacesSearchError?> forStatus(int code) =>
          errorFor(MockClient((_) async => http.Response('{"error":"x"}', code)));
      expect(await forStatus(400), PlacesSearchError.rejected);
      expect(await forStatus(401), PlacesSearchError.notConfigured);
      expect(await forStatus(502), PlacesSearchError.server);
      expect(await forStatus(500), PlacesSearchError.server);
    });

    test('a redirect is never followed and counts as a server error', () async {
      for (final code in [301, 302, 307, 308]) {
        final requests = <http.BaseRequest>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response('', code, headers: {'location': 'https://elsewhere.example/collect'});
        });
        expect(await errorFor(client), PlacesSearchError.server, reason: '$code');
        expect(requests, hasLength(1), reason: '$code');
        expect(requests.single.followRedirects, isFalse, reason: '$code');
      }
    });

    test('no connection is a network error', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      expect(await errorFor(client), PlacesSearchError.network);
    });

    test('no answer in time is a network error', () async {
      final never = Completer<http.Response>();
      final service = serviceWith(MockClient((_) => never.future), timeout: const Duration(milliseconds: 20));
      await expectLater(
        service.search(query: 'ramen', near: near),
        throwsA(isA<PlacesSearchException>().having((e) => e.error, 'error', PlacesSearchError.network)),
      );
    });
  });

  group('configuration', () {
    test('the endpoint is fixed to Cravera\'s project over HTTPS', () {
      expect(PlacesService.endpoint.scheme, 'https');
      expect(PlacesService.endpoint.toString(), '${AppConstants.supabaseUrl}/functions/v1/places-search');
    });

    test('a SUPABASE_URL in .env cannot redirect the search', () async {
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://otherproject.supabase.co\nSUPABASE_PUBLISHABLE_KEY=sb_publishable_test',
      );
      final hosts = <String>[];
      final service = PlacesService.fromEnv(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await service!.search(query: 'ramen', near: near);
      expect(hosts, [Uri.parse(AppConstants.supabaseUrl).host]);
      dotenv.clean();
    });

    test('close() leaves an injected client open', () {
      final client = _ClosingClient();
      PlacesService(publishableKey: 'k', client: client).close();
      expect(client.closed, isFalse);
    });

    test('fromEnv returns null when .env was never loaded', () {
      expect(PlacesService.fromEnv(), isNull);
    });

    test('fromEnv needs a non-empty publishable key', () {
      PlacesService? withEnv(String env) {
        dotenv.loadFromString(envString: env, isOptional: true);
        return PlacesService.fromEnv();
      }

      expect(withEnv('SUPABASE_PUBLISHABLE_KEY= sb_publishable_test ')?.publishableKey, 'sb_publishable_test');
      expect(withEnv('SUPABASE_PUBLISHABLE_KEY='), isNull);
      expect(withEnv('OTHER=1'), isNull);
      dotenv.clean();
    });
  });
}

/// Records whether close() was called.
class _ClosingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw UnimplementedError();

  @override
  void close() => closed = true;
}
