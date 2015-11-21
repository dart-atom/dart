import 'package:atom_dartlang/sdk.dart';

import '_spec/test.dart';

void register() => registerSuite(new SdkTest());

class SdkTest extends TestSuite {
  SdkManager _manager;

  Map<String, Test> getTests() => {
    '_autoConfigure': _autoConfigure,
    '_sdkDiscovery': _sdkDiscovery,
    // '_hasSdk': _hasSdk,
    // '_getVersion': _getVersion
  };

  setUp() => _manager = new SdkManager();
  tearDown() => _manager?.dispose();

  _autoConfigure() {
    return _manager.tryToAutoConfigure().then((result) {
      print(result);
      expect(result, true);
    });
  }

  _sdkDiscovery() {
    return new SdkDiscovery().discoverSdk().then((String foundSdk) {
      print('discoverSdk: ${foundSdk}');
      expect(foundSdk is String, true);
    });
  }

  // _hasSdk() {
  //   return _manager.tryToAutoConfigure().then((_) {
  //     expect(_manager.sdk != null, true);
  //     expect(_manager.hasSdk, true);
  //   });
  // }
  //
  // _getVersion() {
  //   return _manager.tryToAutoConfigure().then((_) {
  //     return _manager.sdk.getVersion();
  //   }).then((ver) {
  //     expect(ver is String, true);
  //   });
  // }
}
