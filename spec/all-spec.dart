//import '_spec/animals_test.dart' as animals_test;
//import '_spec/sample-spec.dart' as sample_spec;

import 'flutter/launch_flutter_test.dart' as launch_flutter_test;
import 'sdk_test.dart' as sdk_test;

// TODO: Move tests over from smoketest.dart.

main() {
  //animals_test.register();
  //sample_spec.main();
  launch_flutter_test.register();
  sdk_test.register();
}
