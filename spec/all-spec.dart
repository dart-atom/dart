//import '_spec/animals_test.dart' as animals_test;
//import '_spec/sample-spec.dart' as sample_spec;

import 'flutter/launch_flutter_test.dart' as launch_flutter_test;
import 'projects_test.dart' as projects_test;
import 'sdk_test.dart' as sdk_test;

main() {
  //animals_test.register();
  //sample_spec.main();
  launch_flutter_test.register();
  projects_test.register();
  sdk_test.register();
}
