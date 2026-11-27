import 'dart:async';
import 'dart:typed_data';
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

    test('sends the previous intent and local hour when given', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'results': [], 'intent': {'textQuery': 'cheap tacos'}}), 200);
      });
      final answer = await serviceWith(client).search(
        query: 'cheaper',
        near: near,
        previousIntent: {'textQuery': 'tacos'},
        localHour: 22,
      );
      final body = jsonDecode(sent.body) as Map;
      expect(body['query'], 'cheaper');
      expect(body['previousIntent'], {'textQuery': 'tacos'});
      expect(body['localHour'], 22);
      expect(answer.intent, {'textQuery': 'cheap tacos'});
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

    test('keeps the photo author, and only an https author link', () {
      final [a, b] = PlacesService.parseResults(jsonEncode({
        'results': [
          result(placeId: 'a', overrides: {'photoAuthor': 'Test Photographer', 'photoAuthorUri': 'https://maps.google.com/maps/contrib/fake'}),
          result(placeId: 'b', overrides: {'photoAuthor': 'Test Photographer', 'photoAuthorUri': 'javascript:alert(1)'}),
        ],
      }));
      expect(a.photoAuthor, 'Test Photographer');
      expect(a.photoAuthorUri, 'https://maps.google.com/maps/contrib/fake');
      expect(b.photoAuthorUri, isNull);
    });

    test('keeps only short plain reasons; none by default', () {
      final [a, b] = PlacesService.parseResults(jsonEncode({
        'results': [
          result(placeId: 'a', overrides: {'reasons': ['In your price range', 42, '', 'x' * 31, 'Close by', 'a', 'b', 'c']}),
          result(placeId: 'b'),
        ],
      }));
      expect(a.reasons, ['In your price range', 'Close by', 'a', 'b']);
      expect(b.reasons, isEmpty);
    });

    test('reads the intent object, or null', () {
      expect(PlacesService.parseIntent(jsonEncode({'results': [], 'intent': {'textQuery': 'tacos'}})), {'textQuery': 'tacos'});
      expect(PlacesService.parseIntent(jsonEncode({'results': [], 'intent': 'tacos'})), isNull);
      expect(PlacesService.parseIntent(jsonEncode({'results': []})), isNull);
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
      expect((await serviceWith(client).search(query: 'ramen', near: near)).results, isEmpty);
    });

    test('broken UTF-8 in a 200 answer is a server error', () async {
      final client = MockClient((_) async => http.Response.bytes([0x7b, 0xff, 0xfe, 0x7d], 200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      expect(await errorFor(client), PlacesSearchError.server);
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

  group('photos', () {
    const name = 'places/fake-1/photos/AbC_123';

    test('asks the photo function and returns a Google image link', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'photoUri': 'https://lh3.googleusercontent.com/p/fake=s800'}), 200);
      });
      final url = await serviceWith(client).photoUrl(name);
      expect(url, 'https://lh3.googleusercontent.com/p/fake=s800');
      expect(sent.url, PlacesService.photoEndpoint);
      expect(sent.headers['apikey'], 'sb_publishable_test');
      expect(jsonDecode(sent.body), {'photoName': name});
      expect(sent.followRedirects, isFalse);
    });

    test('anything unexpected is just "no photo"', () async {
      Future<String?> answer(http.Response response) =>
          serviceWith(MockClient((_) async => response)).photoUrl(name);
      expect(await answer(http.Response(jsonEncode({'photoUri': 'https://evil.example/x'}), 200)), isNull);
      expect(await answer(http.Response(jsonEncode({'photoUri': 'http://lh3.googleusercontent.com/x'}), 200)), isNull);
      expect(await answer(http.Response('{"error":"x"}', 502)), isNull);
      expect(await answer(http.Response('not json', 200)), isNull);
      expect(await serviceWith(MockClient((_) async => throw http.ClientException('offline'))).photoUrl(name), isNull);
    });

    const link = 'https://lh3.googleusercontent.com/p/fake=s800';

    /// First answers the photo function with [link], then the image request with [image].
    MockClient photoServer(http.Response image, List<http.BaseRequest> requests) => MockClient((request) async {
          requests.add(request);
          if (request.url == PlacesService.photoEndpoint) {
            return http.Response(jsonEncode({'photoUri': link}), 200);
          }
          return image;
        });

    test('downloads the image itself from the Google link', () async {
      final requests = <http.BaseRequest>[];
      final bytes = await serviceWith(photoServer(
        http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/jpeg'}),
        requests,
      )).photoBytes(name);
      expect(bytes, [1, 2, 3]);
      expect(requests.map((r) => r.url.toString()), [PlacesService.photoEndpoint.toString(), link]);
      expect(requests.last.followRedirects, isFalse);
    });

    test('a redirect from the image host is never followed', () async {
      final requests = <http.BaseRequest>[];
      final bytes = await serviceWith(photoServer(
        http.Response('', 302, headers: {'location': 'https://elsewhere.example/collect'}),
        requests,
      )).photoBytes(name);
      expect(bytes, isNull);
      expect(requests, hasLength(2), reason: 'no request to the redirect target');
      expect(requests.any((r) => r.url.host == 'elsewhere.example'), isFalse);
    });

    test('not an image, empty, or too large is "no photo"', () async {
      Future<Uint8List?> bytesFor(http.Response image) => serviceWith(photoServer(image, [])).photoBytes(name);
      expect(await bytesFor(http.Response('<html>', 200, headers: {'content-type': 'text/html'})), isNull);
      expect(await bytesFor(http.Response.bytes([], 200, headers: {'content-type': 'image/jpeg'})), isNull);
      expect(
        await bytesFor(http.Response.bytes(
          Uint8List(PlacesService.maxPhotoBytes + 1),
          200,
          headers: {'content-type': 'image/jpeg'},
        )),
        isNull,
      );
    });

    test('an endless image with no size stops being read just past the limit', () async {
      var sent = 0;
      final endless = StreamController<List<int>>();
      void pump() {
        // Feed 256 KB chunks until the reader cancels.
        if (endless.isClosed || endless.isPaused) return;
        endless.add(Uint8List(256 * 1024));
        sent += 256 * 1024;
        if (sent < 100 * 1024 * 1024) scheduleMicrotask(pump);
      }

      endless.onListen = pump;
      endless.onResume = pump;
      var cancelled = false;
      endless.onCancel = () => cancelled = true;
      final client = MockClient.streaming((request, body) async {
        if (request.url == PlacesService.photoEndpoint) {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'photoUri': link}))), 200);
        }
        return http.StreamedResponse(endless.stream, 200, headers: {'content-type': 'image/jpeg'});
      });

      expect(await serviceWith(client).photoBytes(name), isNull);
      expect(cancelled, isTrue, reason: 'the download is stopped');
      // A few chunks may already be in flight when it cancels; it must stop near the limit, not read 100 MB.
      expect(sent, lessThan(PlacesService.maxPhotoBytes + 1024 * 1024), reason: 'not read to the end');
    });

    test('a declared size over the limit is refused before reading', () async {
      var bodyRead = false;
      final client = MockClient.streaming((request, body) async {
        if (request.url == PlacesService.photoEndpoint) {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'photoUri': link}))), 200);
        }
        final image = StreamController<List<int>>(onListen: () => bodyRead = true);
        return http.StreamedResponse(image.stream, 200,
            contentLength: PlacesService.maxPhotoBytes + 1, headers: {'content-type': 'image/jpeg'});
      });
      expect(await serviceWith(client).photoBytes(name), isNull);
      expect(bodyRead, isTrue, reason: 'the stream is drained to free the connection, but nothing is kept');
    });

    test('a name that is not a Places photo name is never sent', () async {
      var calls = 0;
      final service = serviceWith(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));
      expect(await service.photoUrl('places/x/reviews/y'), isNull);
      expect(await service.photoUrl('https://evil.example/places/x/photos/y'), isNull);
      expect(calls, 0);
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
