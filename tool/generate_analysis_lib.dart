
import 'dart:io';

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

import 'src/src_gen.dart';

main(List<String> args) {
  // Parse spec_input.html into a model.
  File file = new File('tool/spec_input.html');
  Document document = parse(file.readAsStringSync());
  print('Parsed ${file.path}.');
  List<Element> elements = document.body.getElementsByTagName('domain');
  Api api = new Api(elements);

  // Generate code from the model.
  File outputFile = new File('lib/impl/analysis_server_gen.dart');
  DartGenerator generator = new DartGenerator();
  api.generate(generator);
  outputFile.writeAsStringSync(generator.toString());
  print('Wrote ${outputFile.path}.');
}

class Api {
  List<Domain> domains;

  Api(List<Element> domainElements) {
    domains = domainElements.map((element) => new Domain(element)).toList();
  }

  void generate(DartGenerator gen) {
    gen.writeln('// This is a generated file.');
    gen.writeln();
    gen.writeln('library analysis_server_gen;');
    gen.writeln();
    gen.write(_serverClient);
    domains.forEach((Domain domain) => domain.generate(gen));
  }

  String toString() => domains.toString();
}

class Domain {
  String name;
  List<Request> requests;

  Domain(Element element) {
    // <domain name="server">
    name = element.attributes['name'];
    requests = element.getElementsByTagName('request').map(
        (element) => new Request(element)).toList();
  }

  String get className => '${titleCase(name)}Domain';

  void generate(DartGenerator gen) {
    gen.writeln();
    gen.writeStatement('class ${className} extends Domain {');
    gen.writeStatement("${className}(ServerClient client) : super(client, '${name}');");
    gen.writeln();
    //requests.forEach((Request request) => request.generate(gen));
    gen.writeln('}');
  }

  String toString() => "Domain '${name}': ${requests}";
}

class Request {
  String method;

  Request(Element element) {
    // <request method="getVersion">
    method = element.attributes['method'];

    // TODO: <params>, <result>

  }

  String toString() => 'Request ${method}()';
}

final String _serverClient = r'''
class ServerClient {

}

abstract class Domain {
  final ServerClient client;
  final String name;

  Domain(this.client, this.name);

  String toString() => 'Domain ${name}';
}
''';
