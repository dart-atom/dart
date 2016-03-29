import 'package:atom_dartlang/sdk.dart';

import '_spec/test.dart';

void register() => registerSuite(new SdkTest());

class SdkTest extends TestSuite {
  Map<String, Test> getTests() => {
    '_autoConfigure': autoConfigure,
    '_sdkDiscovery': sdkDiscovery
  };

  SdkManager _manager;

  setUp() => _manager = new SdkManager();
  tearDown() => _manager?.dispose();

  autoConfigure() {
    return _manager.tryToAutoConfigure().then((result) {
      print(result);
      expect(result, true);
    });
  }

  sdkDiscovery() {
    return new SdkDiscovery().discoverSdk().then((String foundSdk) {
      print('discoverSdk: ${foundSdk}');
      expect(foundSdk is String, true);
    });
  }
}
