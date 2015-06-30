import 'dart:io';

import 'package:markdown/markdown.dart';

import 'src/parser.dart';
import 'src/src_gen.dart';

Api api;

bool _isPara(Node node) => node is Element && node.tag == 'p';
bool _isPre(Node node) => node is Element && node.tag == 'pre';
bool _isH3(Node node) => node is Element && node.tag == 'h3';
bool _isHeader(Node node) => node is Element && node.tag.startsWith('h');
String _textForElement(Node node) => (((node as Element).children.first) as Text).text;
String _textForCode(Node node) => _textForElement((node as Element).children.first);

String _coerceRefType(String typeName) {
  if (typeName == 'Object') typeName = 'Obj';
  if (typeName == '@Object') typeName = 'ObjRef';
  if (typeName == 'Function') typeName = 'Func';
  if (typeName == '@Function') typeName = 'FuncRef';
  if (typeName.startsWith('@')) typeName = typeName.substring(1) + 'Ref';
  if (typeName == 'string') typeName = 'String';
  return typeName;
}

main(List<String> args) {
  // Parse service.md into a model.
  File file = new File('tool/service.md');
  Document document = new Document();
  List<Node> nodes = document.parseLines(file.readAsStringSync().split('\n'));
  print('Parsed ${file.path}.');
  api = new Api();
  api.parse(nodes);

  // Generate code from the model.
  File outputFile = new File('lib/impl/observatory_gen.dart');
  DartGenerator generator = new DartGenerator();
  api.generate(generator);
  outputFile.writeAsStringSync(generator.toString());
  print('Wrote ${outputFile.path}.');
}

final String _headerCode = r'''
// This is a generated file.

library observatory_gen;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

final Logger _logger = new Logger('observatory_gen');

const optional = 'optional';

''';

final String _implCode = r'''

  Stream<String> get onSend => _onSend.stream;

  Stream<String> get onReceive => _onReceive.stream;

  void dispose() {
    _streamSub.cancel();
    _completers.values.forEach((c) => c.completeError('disposed'));
  }

  Future<Response> _call(String method, [Map args = const {}]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    // TODO: The observatory needs 'params' to be there...
    Map m = {'id': id, 'method': method, 'params': args};
    if (args != null) m['params'] = args;
    String message = JSON.encode(m);
    _onSend.add(message);
    _writeMessage(message);
    return _completers[id].future;
  }

  void _processMessage(String message) {
    try {
      _onReceive.add(message);

      var json = JSON.decode(message);

      if (json['event'] != null) {
        String streamId = json['streamId'];

        // TODO: These could be generated from a list.

        if (streamId == 'Isolate') {
          _isolateEventController.add(createObject(json['event']));
        } else if (streamId == 'Debug') {
          _debugEventController.add(createObject(json['event']));
        } else if (streamId == 'GC') {
          _gcEventController.add(createObject(json['event']));
        } else {
          _logger.warning('unknown streamId: ${streamId}');
        }
      } else if (json['id'] != null) {
        Completer completer = _completers.remove(json['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (json['error'] != null) {
          completer.completeError(RPCError.parse(json['error']));
        } else {
          var result = json['result'];
          String type = result['type'];
          if (_typeFactories[type] == null) {
            completer.completeError(new RPCError(0, 'unknown response type ${type}'));
          } else {
            completer.complete(createObject(result));
          }
        }
      } else {
        _logger.severe('unknown message type: ${message}');
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }
''';

final String _rpcError = r'''
Object createObject(dynamic json) {
  if (json == null) return null;

  if (json is List) {
    return (json as List).map((e) => createObject(e)).toList();
  } else if (json is Map) {
    String type = json['type'];
    if (_typeFactories[type] == null) {
      _logger.severe("no factory for type '${type}'");
      return null;
    } else {
      return _typeFactories[type](json);
    }
  } else {
    // Handle simple types.
    return json;
  }
}

Object _parseEnum(Iterable itor, String valueName) {
  if (valueName == null) return null;
  return itor.firstWhere((i) => i.toString() == valueName, orElse: () => null);
}

class RPCError {
  static RPCError parse(dynamic json) {
    return new RPCError(json['code'], json['message'], json['data']);
  }

  final int code;
  final String message;
  final Map data;

  RPCError(this.code, this.message, [this.data]);

  String toString() => '${code}: ${message}';
}
''';

abstract class Member {
  String get name;
  String get docs => null;
  void generate(DartGenerator gen);

  bool get hasDocs => docs != null;

  String toString() => name;
}

class Api extends Member {
  List<Method> methods = [];
  List<Enum> enums = [];
  List<Type> types = [];

  void parse(List<Node> nodes) {
    // Look for h3 nodes
    // the pre following it is the definition
    // the optional p following that is the dcumentation

    String h3Name = null;

    for (int i = 0; i < nodes.length; i++) {
      Node node = nodes[i];

      if (_isPre(node) && h3Name != null) {
        String definition = _textForCode(node);
        String docs = null;

        if (i + 1 < nodes.length && _isPara(nodes[i + 1])) {
          Element p = nodes[++i];
          docs = collapseWhitespace(TextOutputVisitor.printText(p));
        }

        _parse(h3Name, definition, docs);
      } else if (_isH3(node)) {
        h3Name = _textForElement(node);
      } else if (_isHeader(node)) {
        h3Name = null;
      }
    }
  }

  String get name => 'api';
  String get docs => null;

  void _parse(String name, String definition, [String docs]) {
    name = name.trim();
    definition = definition.trim();
    if (docs != null) docs = docs.trim();

    if (name.substring(0, 1).toLowerCase() == name.substring(0, 1)) {
      methods.add(new Method(name, definition, docs));
    } else if (definition.startsWith('class ')) {
      types.add(new Type(this, name, definition, docs));
    } else if (definition.startsWith('enum ')) {
      enums.add(new Enum(name, definition, docs));
    } else {
      throw 'unexpected entity: ${name}, ${definition}';
    }
  }

  static String printNode(Node n) {
    if (n is Text) {
      return n.text;
    } else if (n is Element) {
      if (n.tag != 'h3') return n.tag;
      return '${n.tag}:[${n.children.map((c) => printNode(c)).join(', ')}]';
    } else {
      return '${n}';
    }
  }

  void generate(DartGenerator gen) {
    gen.out(_headerCode);
    gen.write('Map<String, Function> _typeFactories = {');
    types.forEach((Type type) {
      //if (type.isResponse)
      gen.write("'${type.rawName}': ${type.name}.parse");
      gen.writeln(type == types.last ? '' : ',');
    });
    gen.writeln('};');
    gen.writeln();
    gen.writeStatement('class Observatory {');
    gen.writeStatement('StreamSubscription _streamSub;');
    gen.writeStatement('Function _writeMessage;');
    gen.writeStatement('int _id = 0;');
    gen.writeStatement('Map<String, Completer> _completers = {};');
    gen.writeln();
    gen.writeln("StreamController _onSend = new StreamController.broadcast();");
    gen.writeln("StreamController _onReceive = new StreamController.broadcast();");
    gen.writeln();
    gen.writeln("StreamController<Event> _isolateEventController = new StreamController.broadcast();");
    gen.writeln("StreamController<Event> _debugEventController = new StreamController.broadcast();");
    gen.writeln("StreamController<Event> _gcEventController = new StreamController.broadcast();");
    gen.writeln();
    gen.writeStatement(
        'Observatory(Stream<String> inStream, void writeMessage(String message)) {');
    gen.writeStatement('_streamSub = inStream.listen(_processMessage);');
    gen.writeStatement('_writeMessage = writeMessage;');
    gen.writeln('}');
    gen.writeln();
    gen.writeln("Stream<Event> get onIsolateEvent => _isolateEventController.stream;");
    gen.writeln();
    gen.writeln("Stream<Event> get onDebugEvent => _debugEventController.stream;");
    gen.writeln();
    gen.writeln("Stream<Event> get onGcEvent => _gcEventController.stream;");
    methods.forEach((m) => m.generate(gen));
    gen.out(_implCode);
    gen.writeStatement('}');
    gen.writeln();
    gen.writeln(_rpcError);
    gen.writeln('// enums');
    enums.forEach((e) => e.generate(gen));
    gen.writeln();
    gen.writeln('// types');
    types.forEach((t) => t.generate(gen));
  }

  bool isEnumName(String typeName) => enums.any((Enum e) => e.name == typeName);

  Type getType(String name) =>
      types.firstWhere((t) => t.name == name, orElse: () => null);
}

class Method extends Member {
  final String name;
  final String docs;

  MemberType returnType = new MemberType();
  List<MethodArg> args = [];

  Method(this.name, String definition, [this.docs]) {
    _parse(new Tokenizer(definition).tokenize());
  }

  bool get hasArgs => args.isNotEmpty;

  bool get hasOptionalArgs => args.any((MethodArg arg) => arg.optional);

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) {
      String _docs = docs == null ? '' : docs;
      if (returnType.isMultipleReturns) {
        _docs += '\n\nThe return value can be one of '
            '${joinLast(returnType.types.map((t) => '[${t}]'), ', ', ' or ')}.';
        _docs = _docs.trim();
      }
      if (_docs.isNotEmpty) gen.writeDocs(_docs);
      gen.write('Future<${returnType.name}> ${name}(');
      gen.write(args.map((MethodArg arg) {
        if (arg.optional) {
          return '[${arg.type} ${arg.name}]';
        } else {
          return '${arg.type} ${arg.name}';
        }
      }).join(', '));
      gen.write(') ');
      if (!hasArgs) {
        gen.writeStatement("=> _call('${name}');");
      } else if (hasOptionalArgs) {
        gen.writeStatement('{');
        gen.write('Map m = {');
        gen.write(args.where((MethodArg a) => !a.optional).map(
            (arg) => "'${arg.name}': ${arg.name}").join(', '));
        gen.writeln('};');
        args.where((MethodArg a) => a.optional).forEach((MethodArg arg) {
          String valueRef = arg.name;
          if (api.isEnumName(arg.type)) {
            valueRef = '${arg.name}.toString()';
          }
          gen.writeln("if (${arg.name} != null) m['${arg.name}'] = ${valueRef};");
        });
        gen.writeStatement("return _call('${name}', m);");
        gen.writeStatement('}');
      } else {
        gen.writeStatement('{');
        gen.write("return _call('${name}', {");
        gen.write(args.map((arg) => "'${arg.name}': ${arg.name}").join(', '));
        gen.writeStatement('});');
        gen.writeStatement('}');
      }
    }
  }

  void _parse(Token token) {
    new MethodParser(token).parseInto(this);
  }
}

class MemberType extends Member {
  List<TypeRef> types = [];

  MemberType();

  void parse(Parser parser) {
    // foo|bar[]|baz
    bool loop = true;
    while (loop) {
      Token t = parser.expectName();
      TypeRef ref = new TypeRef(_coerceRefType(t.text));
      while (parser.consume('[')) {
        parser.expect(']');
        ref.arrayDepth++;
      }
      types.add(ref);
      loop = parser.consume('|');
    }
  }

  String get name {
    if (types.isEmpty) return '';
    if (types.length == 1) return types.first.ref;
    return 'dynamic';
  }

  bool get isMultipleReturns => types.length > 1;

  bool get isSimple => types.length == 1 && types.first.isSimple;

  bool get isEnum => types.length == 1 && api.isEnumName(types.first.name);

  void generate(DartGenerator gen) => gen.write(name);
}

class TypeRef {
  String name;
  int arrayDepth = 0;

  TypeRef(this.name);

  String get ref => arrayDepth == 2
      ? 'List<List<${name}>>' : arrayDepth == 1 ? 'List<${name}>' : name;

  bool get isArray => arrayDepth > 0;

  bool get isSimple => name == 'int' || name == 'String' || name == 'bool';

  String toString() => ref;
}

class MethodArg extends Member {
  final Method parent;
  String type;
  String name;
  bool optional = false;

  MethodArg(this.parent, this.type, this.name);

  void generate(DartGenerator gen) => gen.write('${type} ${name}');
}

class Type extends Member {
  final Api parent;
  String rawName;
  String name;
  String superName;
  final String docs;
  List<TypeField> fields = [];

  Type(this.parent, String categoryName, String definition, [this.docs]) {
    _parse(new Tokenizer(definition).tokenize());
  }

  bool get isResponse {
    if (superName == null) return false;
    if (name == 'Response' || superName == 'Response') return true;
    return parent.getType(superName).isResponse;
  }

  bool get isRef => name.endsWith('Ref');

  Type getSuper() => superName == null ? null : api.getType(superName);

  List<TypeField> getAllFields() {
    if (superName == null) return fields;

    List<TypeField> all = [];
    all.insertAll(0, fields);

    Type s = getSuper();
    while (s != null) {
      all.insertAll(0, s.fields);
      s = s.getSuper();
    }

    return all;
  }

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) gen.writeDocs(docs);
    gen.write('class ${name} ');
    if (superName != null) gen.write('extends ${superName} ');
    gen.writeln('{');
    gen.writeln('static ${name} parse(Map json) => new ${name}.fromJson(json);');
    gen.writeln();
    gen.writeln('${name}();');
    String superCall = superName == null ? '' : ": super.fromJson(json) ";
    gen.writeln('${name}.fromJson(Map json) ${superCall}{');
    fields.forEach((TypeField field) {
      if (field.type.isSimple) {
        gen.writeln("${field.generatableName} = json['${field.name}'];");
      } else if (field.type.isEnum) {
        // Parse the enum.
        String enumTypeName = field.type.types.first.name;
        gen.writeln(
          "${field.generatableName} = _parseEnum(${enumTypeName}.values, json['${field.name}']);");
      } else {
        gen.writeln("${field.generatableName} = createObject(json['${field.name}']);");
      }
    });
    gen.writeln('}');
    gen.writeln();
    fields.forEach((TypeField field) => field.generate(gen));

    List<TypeField> allFields = getAllFields();
    if (allFields.length <= 7) {
      String properties = allFields.map(
        (TypeField f) => "${f.generatableName}: \${${f.generatableName}}").join(', ');
      if (properties.length > 70) {
        gen.writeln("String toString() => '[${name} ' //\n'${properties}]';");
      } else {
        gen.writeln("String toString() => '[${name} ${properties}]';");
      }
    } else {
      gen.writeln("String toString() => '[${name}]';");
    }

    gen.writeln('}');
  }

  void _parse(Token token) {
    new TypeParser(token).parseInto(this);
  }
}

class TypeField extends Member {
  static final Map<String, String> _nameRemap = {
    'const': 'isConst',
    'final': 'isFinal',
    'static': 'isStatic',
    'abstract': 'isAbstract',
    'super': 'superClass',
    'class': 'classRef'
  };

  final Type parent;
  final String _docs;
  MemberType type = new MemberType();
  String name;
  bool optional = false;

  TypeField(this.parent, this._docs);

  String get docs {
    String str = _docs == null ? '' : _docs;
    if (type.isMultipleReturns) {
      str += '\n\n[${generatableName}] can be one of '
          '${joinLast(type.types.map((t) => '[${t}]'), ', ', ' or ')}.';
      str = str.trim();
    }
    return str;
  }

  String get generatableName {
    return _nameRemap[name] != null ? _nameRemap[name] : name;
  }

  void generate(DartGenerator gen) {
    if (docs.isNotEmpty) gen.writeDocs(docs);
    if (optional) gen.write('@optional ');
    gen.writeStatement('${type.name} ${generatableName};');
    if (parent.fields.any((field) => field.hasDocs)) gen.writeln();
  }
}

class Enum extends Member {
  final String name;
  final String docs;

  List<EnumValue> enums = [];

  Enum(this.name, String definition, [this.docs]) {
    _parse(new Tokenizer(definition).tokenize());
  }

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) gen.writeDocs(docs);
    gen.writeStatement('enum ${name} {');
    enums.forEach((EnumValue val) => val.generate(gen));
    gen.writeStatement('}');
  }

  void _parse(Token token) {
    new EnumParser(token).parseInto(this);
  }
}

class EnumValue extends Member {
  final Enum parent;
  final String name;
  final String docs;

  EnumValue(this.parent, this.name, [this.docs]);

  bool get isLast => parent.enums.last == this;

  void generate(DartGenerator gen) {
    if (docs != null) gen.writeDocs(docs);
    gen.write('${name}');
    if (!isLast) gen.write(',');
    gen.writeln();
  }
}

class TextOutputVisitor implements NodeVisitor {
  static String printText(Node node) {
    TextOutputVisitor visitor = new TextOutputVisitor();
    node.accept(visitor);
    return visitor.toString();
  }

  StringBuffer buf = new StringBuffer();
  bool _inRef = false;

  TextOutputVisitor();

  void visitText(Text text) {
    String t = text.text;
    if (_inRef) t = _coerceRefType(t);
    buf.write(t);
  }

  bool visitElementBefore(Element element) {
    if (element.tag == 'em') {
      buf.write('[');
      _inRef = true;
    } else if (element.tag == 'p') {
      // Nothing to do.
    } else if (element.tag == 'a') {
      // Nothing to do - we're not writing out <a> refs (they won't resolve).
    } else {
      print('unknown tag: ${element.tag}');
      buf.write(renderToHtml([element]));
    }

    return true;
  }

  void visitElementAfter(Element element) {
    if (element.tag == 'p') {
      buf.write('\n\n');
    } else if (element.tag == 'em') {
      buf.write(']');
      _inRef = false;
    }
  }

  String toString() => buf.toString().trim();
}

// @Instance|@Error|Sentinel evaluate(
//     string isolateId,
//     string targetId [optional],
//     string expression)
class MethodParser extends Parser {
  MethodParser(Token startToken) : super(startToken);

  void parseInto(Method method) {
    // method is return type, name, (, args )
    // args is type name, [optional], comma

    method.returnType.parse(this);

    Token t = expectName();
    validate(t.text == method.name, 'method name ${method.name} equals ${t.text}');

    expect('(');

    while (peek().text != ')') {
      Token type = expectName();
      Token name = expectName();
      MethodArg arg = new MethodArg(method, _coerceRefType(type.text), name.text);
      if (consume('[')) {
        expect('optional');
        expect(']');
        arg.optional = true;
      }
      method.args.add(arg);
      consume(',');
    }

    expect(')');
  }
}

class TypeParser extends Parser {
  TypeParser(Token startToken) : super(startToken);

  void parseInto(Type type) {
    // class ClassList extends Response {
    //   // Docs here.
    //   @Class[] classes [optional];
    // }
    expect('class');

    Token t = expectName();
    type.rawName = t.text;
    type.name = _coerceRefType(type.rawName);
    if (consume('extends')) {
      t = expectName();
      type.superName = _coerceRefType(t.text);
    }

    expect('{');

    while (peek().text != '}') {
      TypeField field = new TypeField(type, collectComments());
      field.type.parse(this);
      field.name = expectName().text;
      if (consume('[')) {
        expect('optional');
        expect(']');
        field.optional = true;
      }
      type.fields.add(field);
      expect(';');
    }

    expect('}');
  }
}

class EnumParser extends Parser {
  EnumParser(Token startToken) : super(startToken);

  void parseInto(Enum e) {
    // enum ErrorKind { UnhandledException, Foo, Bar }
    // enum name { (comment* name ,)+ }
    expect('enum');

    Token t = expectName();
    validate(t.text == e.name, 'enum name ${e.name} equals ${t.text}');
    expect('{');

    while (!t.eof) {
      if (consume('}')) break;
      String docs = collectComments();
      t = expectName();
      consume(',');

      e.enums.add(new EnumValue(e, t.text, docs));
    }
  }
}
