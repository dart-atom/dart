
library generate_analysis_lib;

import 'dart:collection' show LinkedHashMap;
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import '../src/src_gen.dart';

Api api;

main(List<String> args) {
  // Parse spec_input.html into a model.
  File file = new File('tool/analysis/spec_input.html');
  Document document = parse(file.readAsStringSync());
  print('Parsed ${file.path}.');
  Element ver = document.body.querySelector('version');
  List<Element> domains = document.body.getElementsByTagName('domain');
  List<Element> typedefs = document.body.getElementsByTagName('types')
      .first.getElementsByTagName('type');
  List<Element> refactorings = document.body.getElementsByTagName('refactorings')
      .first.getElementsByTagName('refactoring');
  api = new Api(ver.text);
  api.parse(domains, typedefs, refactorings);

  // Generate code from the model.
  File outputFile = new File('lib/analysis/analysis_server_lib.dart');
  DartGenerator generator = new DartGenerator();
  api.generate(generator);
  outputFile.writeAsStringSync(generator.toString());
  print('Wrote ${outputFile.path}.');
}

class Api {
  final String version;

  List<Domain> domains;
  List<TypeDef> typedefs;
  List<Refactoring> refactorings;

  Api(this.version);

  void parse(List<Element> domainElements, List<Element> typeElements,
      List<Element> refactoringElements) {
    typedefs = new List.from(typeElements.map((element) => new TypeDef(element)));
    domains = new List.from(domainElements.map((element) => new Domain(element)));
    refactorings = new List.from(refactoringElements.map((e) => new Refactoring(e)));

    // Mark some types as jsonable - we can send them back over the wire.
    findRef('SourceEdit').setCallParam();
    typedefs
        .where((def) => def.name.endsWith('ContentOverlay'))
        .forEach((def) => def.setCallParam());
  }

  TypeDef findRef(String name) =>
      typedefs.firstWhere((TypeDef t) => t.name == name);

  void generate(DartGenerator gen) {
    gen.out(_headerCode);
    gen.writeln("const String generatedProtocolVersion = '${version}';");
    gen.writeln();
    gen.writeln("typedef void MethodSend(String methodName);");
    gen.writeln();
    gen.writeStatement('class Server {');
    gen.writeStatement('StreamSubscription _streamSub;');
    gen.writeStatement('Function _writeMessage;');
    gen.writeStatement('int _id = 0;');
    gen.writeStatement('Map<String, Completer> _completers = {};');
    gen.writeStatement('Map<String, String> _methodNames = {};');
    gen.writeln(
        'JsonCodec _jsonEncoder = new JsonCodec(toEncodable: _toEncodable);');
    gen.writeStatement('Map<String, Domain> _domains = {};');
    gen.writeln("StreamController<String> _onSend = new StreamController.broadcast();");
    gen.writeln("StreamController<String> _onReceive = new StreamController.broadcast();");
    gen.writeln("MethodSend _willSend;");
    gen.writeln();
    domains.forEach(
        (Domain domain) => gen.writeln('${domain.className} _${domain.name};'));
    gen.writeln();
    gen.writeStatement(
        'Server(Stream<String> inStream, void writeMessage(String message)) {');
    gen.writeStatement('configure(inStream, writeMessage);');
    gen.writeln();
    domains.forEach((Domain domain) =>
        gen.writeln('_${domain.name} = new ${domain.className}(this);'));
    gen.writeln('}');
    gen.writeln();
    domains.forEach((Domain domain) => gen
        .writeln('${domain.className} get ${domain.name} => _${domain.name};'));
    gen.writeln();
    gen.out(_serverCode);
    gen.writeln('}');
    gen.writeln();

    // abstract Domain
    gen.out(_domainCode);

    // individual domains
    domains.forEach((Domain domain) => domain.generate(gen));

    // Object definitions.
    gen.writeln();
    gen.writeln('// type definitions');
    gen.writeln();
    typedefs
        .where((t) => t.isObject)
        .forEach((TypeDef def) => def.generate(gen));

    // Handle the refactorings items.
    gen.writeln();
    gen.writeln('// refactorings');
    gen.writeln();
    gen.writeStatement('class Refactorings {');
    refactorings.forEach((Refactoring refactor) {
      gen.writeStatement("static const String ${refactor.kind} = '${refactor.kind}';");
    });
    gen.writeStatement('}');

    refactorings.forEach((Refactoring refactor) => refactor.generate(gen));

    // Refactoring feedback.
    gen.writeln();
    refactorings.forEach((Refactoring refactor) {
      if (refactor.feedbackFields.isEmpty) return;

      gen.writeln("// ${refactor.kind}:");
      for (Field field in refactor.feedbackFields) {
        gen.writeln(
          "//   ${field.optional ? '@optional ' : ''}${field.name} → ${field.type}");
      }
      gen.writeln();
    });
    gen.writeStatement('class RefactoringFeedback {');
    gen.writeStatement('static RefactoringFeedback parse(Map m) {');
    gen.writeStatement('return m == null ? null : new RefactoringFeedback(m);');
    gen.writeStatement('}');
    gen.writeln();
    gen.writeStatement('final Map _m;');
    gen.writeln();
    gen.writeStatement('RefactoringFeedback(this._m);');
    gen.writeln();
    gen.writeStatement('operator[](String key) => _m[key];');
    gen.writeStatement('}');
  }

  String toString() => domains.toString();
}

class Domain {
  bool experimental = false;
  String name;

  List<Request> requests;
  List<Notification> notifications;
  Map<String, List<Field>> resultClasses = new LinkedHashMap();

  Domain(Element element) {
    name = element.attributes['name'];
    experimental = element.attributes.containsKey('experimental');
    requests = new List.from(element
      .getElementsByTagName('request')
      .map((element) => new Request(this, element))
    );
    notifications = new List.from(element
      .getElementsByTagName('notification')
      .map((element) => new Notification(this, element))
    );
  }

  String get className => '${titleCase(name)}Domain';

  void generate(DartGenerator gen) {
    resultClasses.clear();
    gen.writeln();
    gen.writeln('// ${name} domain');
    gen.writeln();
    if (experimental) gen.writeln('@experimental');
    gen.writeStatement('class ${className} extends Domain {');
    gen.writeStatement("${className}(Server server) : super(server, '${name}');");
    if (notifications.isNotEmpty) {
      gen.writeln();
      notifications
          .forEach((Notification notification) => notification.generate(gen));
    }
    requests.forEach((Request request) => request.generate(gen));
    gen.writeln('}');

    notifications.forEach(
        (Notification notification) => notification.generateClass(gen));

    for (String name in resultClasses.keys) {
      List<Field> fields = resultClasses[name];

      gen.writeln();
      gen.writeStatement('class ${name} {');
      gen.write('static ${name} parse(Map m) => ');
      gen.write('new ${name}(');
      gen.write(fields.map((Field field) {
        String val = "m['${field.name}']";
        if (field.type.isMap) {
          val = 'new Map.from($val)';
        }

        if (field.optional) {
          return "${field.name}: ${field.type.jsonConvert(val)}";
        } else {
          return field.type.jsonConvert(val);
        }
      }).join(', '));
      gen.writeln(');');
      gen.writeln();
      fields.forEach((field) {
        if (field.optional) gen.write('@optional ');
        gen.writeln('final ${field.type} ${field.name};');
      });
      gen.writeln();
      gen.write('${name}(');
      gen.write(fields.map((field) {
        StringBuffer buf = new StringBuffer();
        if (field.optional && fields.firstWhere((a) => a.optional) == field) buf
            .write('{');
        buf.write('this.${field.name}');
        if (field.optional && fields.lastWhere((a) => a.optional) == field) buf
            .write('}');
        return buf.toString();
      }).join(', '));
      gen.writeln(');');
      gen.writeln('}');
    }
  }

  String toString() => "Domain '${name}': ${requests}";
}

class Request {
  final Domain domain;

  bool experimental = false;
  String method;
  List<Field> args = [];
  List<Field> results = [];

  Request(this.domain, Element element) {
    experimental = element.attributes.containsKey('experimental');
    method = element.attributes['method'];

    List paramsList = element.getElementsByTagName('params');
    if (paramsList.isNotEmpty) {
      args = new List.from(paramsList.first
          .getElementsByTagName('field')
          .map((field) => new Field(field)));
    }

    List resultsList = element.getElementsByTagName('result');
    if (resultsList.isNotEmpty) {
      results = new List.from(resultsList.first
          .getElementsByTagName('field')
          .map((field) => new Field(field)));
    }
  }

  void generate(DartGenerator gen) {
    gen.writeln();

    args.forEach((Field field) => field.setCallParam());
    if (results.isNotEmpty) {
      domain.resultClasses[resultName] = results;
    }

    if (experimental) gen.writeln('@experimental');

    if (results.isEmpty) {
      if (args.isEmpty) {
        gen.writeln("Future ${method}() => _call('${domain.name}.${method}');");
        return;
      }

      if (args.length == 1 && !args.first.optional) {
        Field arg = args.first;
        gen.write("Future ${method}(${arg.type} ${arg.name}) => ");
        gen.writeln(
            "_call('${domain.name}.${method}', {'${arg.name}': ${arg.name}});");
        return;
      }
    }

    if (args.isEmpty) {
      gen.writeln(
          "Future<${resultName}> ${method}() => _call('${domain.name}.${method}').then("
          "${resultName}.parse);");
      return;
    }

    if (results.isEmpty) {
      gen.write('Future ${method}(');
    } else {
      gen.write('Future<${resultName}> ${method}(');
    }
    gen.write(args.map((arg) {
      StringBuffer buf = new StringBuffer();
      if (arg.optional && args.firstWhere((a) => a.optional) == arg) buf
          .write('{');
      buf.write('${arg.type} ${arg.name}');
      if (arg.optional && args.lastWhere((a) => a.optional) == arg) buf
          .write('}');
      return buf.toString();
    }).join(', '));
    gen.writeStatement(') {');
    if (args.isEmpty) {
      gen.write("return _call('${domain.name}.${method}')");
      if (results.isNotEmpty) {
        gen.write(".then(${resultName}.parse)");
      }
      gen.writeln(';');
    } else {
      String mapStr = args
          .where((arg) => !arg.optional)
          .map((arg) => "'${arg.name}': ${arg.name}")
          .join(', ');
      gen.writeStatement('Map m = {${mapStr}};');
      for (Field arg in args.where((arg) => arg.optional)) {
        gen.writeStatement(
            "if (${arg.name} != null) m['${arg.name}'] = ${arg.name};");
      }
      gen.write("return _call('${domain.name}.${method}', m)");
      if (results.isNotEmpty) {
        gen.write(".then(${resultName}.parse)");
      }
      gen.writeln(';');
    }
    gen.writeStatement('}');
  }

  String get resultName {
    if (results.isEmpty) return 'dynamic';
    if (method.startsWith('get')) return '${method.substring(3)}Result';
    return '${titleCase(method)}Result';
  }

  String toString() => 'Request ${method}()';
}

class Notification {
  final Domain domain;
  String event;
  List<Field> fields;

  Notification(this.domain, Element element) {
    event = element.attributes['event'];
    fields = new List.from(element
      .getElementsByTagName('field')
      .map((field) => new Field(field))
    );
    fields.sort();
  }

  String get title => '${domain.name}.${event}';

  String get onName => 'on${titleCase(event)}';

  String get className => '${titleCase(domain.name)}${titleCase(event)}';

  void generate(DartGenerator gen) {
    gen.writeln("Stream<${className}> get ${onName} {");
    // TODO: I don't really like having to do this cast.
    gen.writeln("return _listen('${title}', ${className}.parse) as Stream<${className}>;");
    gen.writeln("}");
  }

  void generateClass(DartGenerator gen) {
    gen.writeln();
    gen.writeln('class ${className} {');
    gen.write('static ${className} parse(Map m) => ');
    gen.write('new ${className}(');
    gen.write(fields.map((Field field) {
      String val = "m['${field.name}']";
      if (field.optional) {
        return "${field.name}: ${field.type.jsonConvert(val)}";
      } else {
        return field.type.jsonConvert(val);
      }
    }).join(', '));
    gen.writeln(');');
    if (fields.isNotEmpty) {
      gen.writeln();
      fields.forEach((field) {
        if (field.optional) gen.write('@optional ');
        gen.writeln('final ${field.type} ${field.name};');
      });
    }
    gen.writeln();
    gen.write('${className}(');
    gen.write(fields.map((field) {
      StringBuffer buf = new StringBuffer();
      if (field.optional && fields.firstWhere((a) => a.optional) == field) buf
          .write('{');
      buf.write('this.${field.name}');
      if (field.optional && fields.lastWhere((a) => a.optional) == field) buf
          .write('}');
      return buf.toString();
    }).join(', '));
    gen.writeln(');');
    gen.writeln('}');
  }
}

class Field implements Comparable {
  String name;
  bool optional;
  Type type;

  Field(Element element) {
    name = element.attributes['name'];
    optional = element.attributes['optional'] == 'true';
    type = Type.create(element.children.first);
  }

  void setCallParam() => type.setCallParam();

  String toString() => name;

  int compareTo(other) {
    if (other is! Field) return 0;
    if (!optional && other.optional) return -1;
    if (optional && !other.optional) return 1;
    return 0;
  }

  void generate(DartGenerator gen) {
    if (optional) gen.write('@optional ');
    gen.writeStatement('final ${type} ${name};');
  }
}

class Refactoring {
  String kind;
  List<Field> optionsFields = [];
  List<Field> feedbackFields = [];

  Refactoring(Element element) {
    kind = element.attributes['kind'];

    // Parse <options>
    // <field name="deleteSource"><ref>bool</ref></field>
    Element options = element.querySelector('options');
    if (options != null) {
      optionsFields = new List.from(options
        .getElementsByTagName('field')
        .map((field) => new Field(field))
      );
    }

    // Parse <feedback>
    // <field name="className" optional="true"><ref>String</ref></field>
    Element feedback = element.querySelector('feedback');
    if (feedback != null) {
      feedbackFields = new List.from(feedback
        .getElementsByTagName('field')
        .map((field) => new Field(field))
      );
    }
  }

  String get className {
    // MOVE_FILE ==> MoveFile
    return kind.split('_').map((s) => forceTitleCase(s)).join('');
  }

  void generate(DartGenerator gen) {
    // Generate the refactoring options.
    if (optionsFields.isNotEmpty) {
      gen.writeln();
      gen.writeStatement('class ${className}RefactoringOptions extends RefactoringOptions {');
      // fields
      for (Field field in optionsFields) {
        field.generate(gen);
      }

      gen.writeln();
      gen.writeStatement('${className}RefactoringOptions({'
        '${optionsFields.map((f) => 'this.${f.name}').join(', ')}'
        '});');
      gen.writeln();

      // toMap
      gen.write("Map toMap() => _stripNullValues({");
      gen.write(optionsFields.map((f) => "'${f.name}': ${f.name}").join(', '));
      gen.writeStatement("});");
      gen.writeStatement('}');
    }
  }
}

class TypeDef {
  static final Set<String> _shouldHaveToString = new Set.from([
    'SourceEdit',
    'PubStatus',
    'Location',
    'AnslysisStatus',
    'AnalysisError',
    'SourceChange',
    'SourceFileEdit',
    'LinkedEditGroup',
    'Position',
    'NavigationRegion',
    'NavigationTarget',
    'CompletionSuggestion',
    'Element',
    'SearchResult'
  ]);

  static final Set<String> _shouldHaveEquals = new Set.from([
    'Location',
    'AnalysisError'
  ]);

  String name;
  bool experimental = false;
  bool isString = false;
  List<Field> fields;
  bool _callParam = false;

  TypeDef(Element element) {
    name = element.attributes['name'];
    experimental = element.attributes.containsKey('experimental');

    // object, enum, ref
    Set<String> tags = new Set.from(element.children.map((c) => c.localName));

    if (tags.contains('object')) {
      Element object = element.getElementsByTagName('object').first;
      fields = new List.from(object
        .getElementsByTagName('field')
        .map((f) => new Field(f))
      );
      fields.sort((a, b) {
        if (a.optional && !b.optional) return 1;
        if (!a.optional && b.optional) return -1;
        return 0;
      });
    } else if (tags.contains('enum')) {
      isString = true;
    } else if (tags.contains('ref')) {
      Element tag = element.getElementsByTagName('ref').first;
      String type = tag.text;
      if (type == 'String') {
        isString = true;
      } else {
        throw 'unknown ref type: ${type}';
      }
    } else {
      throw 'unknown tag: ${tags}';
    }
  }

  bool get isObject => fields != null;

  bool get callParam => _callParam;

  void setCallParam() {
    _callParam = true;
  }

  void generate(DartGenerator gen) {
    if (name == 'RefactoringOptions' || name == 'RefactoringFeedback' || name == 'RequestError') {
      return;
    }

    gen.writeln();
    if (experimental) gen.writeln('@experimental');
    gen.writeln('class ${name} ${callParam ? "implements Jsonable " : ""}{');
    gen.writeln('static ${name} parse(Map m) {');
    gen.writeln('if (m == null) return null;');
    gen.write('return new ${name}(');
    gen.write(fields.map((Field field) {
      String val = "m['${field.name}']";
      if (field.optional) {
        return "${field.name}: ${field.type.jsonConvert(val)}";
      } else {
        return field.type.jsonConvert(val);
      }
    }).join(', '));
    gen.writeln(');');
    gen.writeln('}');
    if (fields.isNotEmpty) {
      gen.writeln();
      fields.forEach((field) {
        if (field.optional) gen.write('@optional ');
        gen.writeln('final ${field.type} ${field.name};');
      });
    }
    if (callParam) {
      gen.writeln();
      String map = fields.map((f) => "'${f.name}': ${f.name}").join(', ');
      gen.writeln("Map toMap() => _stripNullValues({${map}});");
    }
    gen.writeln();
    gen.write('${name}(');
    gen.write(fields.map((field) {
      StringBuffer buf = new StringBuffer();
      if (field.optional && fields.firstWhere((a) => a.optional) == field) buf
          .write('{');
      buf.write('this.${field.name}');
      if (field.optional && fields.lastWhere((a) => a.optional) == field) buf
          .write('}');
      return buf.toString();
    }).join(', '));
    gen.writeln(');');

    if (hasEquals) {
      gen.writeln();
      String str = fields.map((f) => "${f.name} == o.${f.name}").join(' && ');
      gen.writeln("operator==(o) => o is ${name} && ${str};");
      gen.writeln();
      String str2 = fields.where((f) => !f.optional).map(
          (f) => "${f.name}.hashCode").join(' ^ ');
      gen.writeln("get hashCode => ${str2};");
    }

    if (hasToString) {
      gen.writeln();
      String str = fields.where((f) => !f.optional).map(
          (f) => "${f.name}: \${${f.name}}").join(', ');
      gen.writeln("String toString() => '[${name} ${str}]';");
    }

    gen.writeln('}');
  }

  bool get hasEquals => _shouldHaveEquals.contains(name);

  bool get hasToString => _shouldHaveToString.contains(name);

  String toString() => 'TypeDef ${name}';
}

abstract class Type {
  String get typeName;

  static Type create(Element element) {
    // <ref>String</ref>, or list, or map
    if (element.localName == 'ref') {
      String text = element.text;
      if (text == 'int' ||
          text == 'bool' ||
          text == 'String' ||
          text == 'long') {
        return new PrimitiveType(text);
      } else {
        return new RefType(text);
      }
    } else if (element.localName == 'list') {
      return new ListType(element.children.first);
    } else if (element.localName == 'map') {
      return new MapType(element.children[0].children.first,
          element.children[1].children.first);
    } else if (element.localName == 'union') {
      return new PrimitiveType('dynamic');
    } else {
      throw 'unknown type: ${element}';
    }
  }

  String jsonConvert(String ref);

  void setCallParam();

  bool get isMap => typeName == 'Map' || typeName.startsWith('Map<');

  String toString() => typeName;
}

class ListType extends Type {
  Type subType;

  ListType(Element element) : subType = Type.create(element);

  String get typeName => 'List<${subType.typeName}>';

  String jsonConvert(String ref) {
    if (subType is PrimitiveType) {
      return "${ref} == null ? null : new List.from(${ref})";
    }

    if (subType is RefType && (subType as RefType).isString) {
      return "${ref} == null ? null : new List.from(${ref})";
    }

    return "${ref} == null ? null : new List.from(${ref}.map((obj) => ${subType.jsonConvert('obj')}))";
  }

  void setCallParam() => subType.setCallParam();
}

class MapType extends Type {
  Type key;
  Type value;

  MapType(Element keyElement, Element valueElement) {
    key = Type.create(keyElement);
    value = Type.create(valueElement);
  }

  String get typeName => 'Map<${key.typeName}, ${value.typeName}>';

  String jsonConvert(String ref) => ref;

  void setCallParam() {
    key.setCallParam();
    value.setCallParam();
  }
}

class RefType extends Type {
  String text;
  TypeDef ref;

  RefType(this.text);

  bool get isString {
    if (ref == null) _resolve();
    return ref.isString;
  }

  String get typeName {
    if (ref == null) _resolve();
    return ref.isString ? 'String' : ref.name;
  }

  String jsonConvert(String r) {
    if (ref == null) _resolve();
    return ref.isString ? r : '${ref.name}.parse(${r})';
  }

  void setCallParam() {
    if (ref == null) _resolve();
    ref.setCallParam();
  }

  void _resolve() {
    try {
      ref = api.findRef(text);
    } catch (e) {
      print("can't resolve ${text}");
      rethrow;
    }
  }
}

class PrimitiveType extends Type {
  final String type;

  PrimitiveType(this.type);

  String get typeName => type == 'long' ? 'int' : type;

  String jsonConvert(String ref) => ref;

  void setCallParam() {}
}

final String _headerCode = r'''
// This is a generated file.

/// A library to access the analysis server API.
library atom.analysis_server_lib;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

/// @optional
const String optional = 'optional';

/// @experimental
const String experimental = 'experimental';

final Logger _logger = new Logger('analysis_server_lib');

''';

final String _serverCode = r'''
  Stream<String> get onSend => _onSend.stream;
  Stream<String> get onReceive => _onReceive.stream;

  set willSend(MethodSend fn) {
    _willSend = fn;
  }

  void configure(Stream<String> inStream, void writeMessage(String message)) {
    dispose();

    _streamSub = inStream.listen(_processMessage);
    _writeMessage = writeMessage;
  }

  void dispose() {
    if (_streamSub != null) _streamSub.cancel();
    //_completers.values.forEach((c) => c.completeError('disposed'));
    _completers.clear();
  }

  void _processMessage(String message) {
    _onReceive.add(message);

    if (!message.startsWith('{')) {
      _logger.warning('unknown message: ${message}');
      return;
    }

    try {
      var json = JSON.decode(message);

      if (json['id'] == null) {
        // Handle a notification.
        String event = json['event'];
        if (event == null) {
          _logger.severe('invalid message: ${message}');
        } else {
          String prefix = event.substring(0, event.indexOf('.'));
          if (_domains[prefix] == null) {
            _logger.severe('no domain for notification: ${message}');
          } else {
            _domains[prefix]._handleEvent(event, json['params']);
          }
        }
      } else {
        Completer completer = _completers.remove(json['id']);
        String methodName = _methodNames.remove(json['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (json['error'] != null) {
          completer.completeError(RequestError.parse(methodName, json['error']));
        } else {
          completer.complete(json['result']);
        }
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }

  Future _call(String method, [Map args]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    _methodNames[id] = method;
    Map m = {'id': id, 'method': method};
    if (args != null) m['params'] = args;
    String message = _jsonEncoder.encode(m);
    if (_willSend != null) _willSend(method);
    _onSend.add(message);
    _writeMessage(message);
    return _completers[id].future;
  }

  static dynamic _toEncodable(obj) => obj is Jsonable ? obj.toMap() : obj;
''';

final String _domainCode = r'''
abstract class Domain {
  final Server server;
  final String name;

  Map<String, StreamController> _controllers = {};
  Map<String, Stream> _streams = {};

  Domain(this.server, this.name) {
    server._domains[name] = this;
  }

  Future _call(String method, [Map args]) => server._call(method, args);

  Stream<dynamic> _listen(String name, Function cvt) {
    if (_streams[name] == null) {
      _controllers[name] = new StreamController.broadcast();
      _streams[name] = _controllers[name].stream.map(cvt);
    }

    return _streams[name];
  }

  void _handleEvent(String name, dynamic event) {
    if (_controllers[name] != null) {
      _controllers[name].add(event);
    }
  }

  String toString() => 'Domain ${name}';
}

abstract class Jsonable {
  Map toMap();
}

abstract class RefactoringOptions implements Jsonable {
}

class RequestError {
  static RequestError parse(String method, Map m) {
    if (m == null) return null;
    return new RequestError(method, m['code'], m['message'], stackTrace: m['stackTrace']);
  }

  final String method;
  final String code;
  final String message;
  @optional final String stackTrace;

  RequestError(this.method, this.code, this.message, {this.stackTrace});

  String toString() => '[Analyzer RequestError method: ${method}, code: ${code}, message: ${message}]';
}

Map _stripNullValues(Map m) {
  Map copy = {};

  for (var key in m.keys) {
    var value = m[key];
    if (value != null) copy[key] = value;
  }

  return copy;
}
''';
