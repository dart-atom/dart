import 'dart:collection' show LinkedHashMap;
import 'dart:io';

import 'package:markdown/markdown.dart';

import 'src/src_gen.dart';

Api api;

bool _isPara(Node node) => node is Element && node.tag == 'p';
bool _isPre(Node node) => node is Element && node.tag == 'pre';
bool _isH3(Node node) => node is Element && node.tag == 'h3';
bool _isHeader(Node node) => node is Element && node.tag.startsWith('h');
String _textForElement(Node node) => (((node as Element).children.first) as Text).text;
String _textForCode(Node node) => _textForElement((node as Element).children.first);

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

abstract class Member {
  String get name;
  String get docs;
  void generate(DartGenerator gen);
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
          //docs = collapseWhitespace(renderToHtml([p]));
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
      types.add(new Type(name, definition, docs));
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
    gen.writeStatement('class Observatory {');
    gen.writeln();
    methods.forEach((m) => m.generate(gen));
    gen.writeStatement('}');
    gen.writeln();
    gen.writeln('// enums');
    enums.forEach((e) => e.generate(gen));
    gen.writeln();
    gen.writeln('// types');
    types.forEach((t) => t.generate(gen));
  }
}

class Method extends Member {
  final String name;
  final String docs;

  Method(this.name, String definition, [this.docs]) {

  }

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) {
      gen.writeDocs(docs);
      gen.writeStatement('Future ${name}() {');
      gen.writeln();
      gen.writeStatement('}');
    }
  }
}

class Type extends Member {
  String name;
  final String docs;

  Type(String categoryName, String definition, [this.docs]) {
    // TODO: parse the name
    // TODO: temp!
    this.name = categoryName;
    if (definition.startsWith('class @')) {
      this.name += 'Ref';
    }
    // TODO: temp!
  }

  // TODO:
  bool get isRef => false;

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) {
      gen.writeDocs(docs);
      gen.writeStatement('class ${name} {');
      gen.writeln();
      gen.writeStatement('}');
    }
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

final String _headerCode = r'''
// This is a generated file.

library observatory_gen;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

final Logger _logger = new Logger('observatory_gen');

const optional = 'optional';

''';

final RegExp _wsRegexp = new RegExp(r'\s+');

String collapseWhitespace(String str) => str.replaceAll(_wsRegexp, ' ');

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

    if (_inRef && t.startsWith('@')) {
      t = t.substring(1) + 'Ref';
    }

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

class Token {
  static final RegExp _alpha = new RegExp(r'^[0-9a-zA-Z_\-@]+$');

  final String text;
  Token next;

  Token(this.text);

  bool get eof => text == null;

  bool get isName {
    if (text == null || text.isEmpty) return false;
    return _alpha.hasMatch(text);
  }

  bool get isComment => text != null && text.startsWith('//');

  String toString() => text == null ? 'EOF' : text;
}

class Tokenizer {
  static final alphaNum =
      '@abcdefghijklmnopqrstuvwxyz-_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static final whitespace = ' \n\t\r';

  String text;
  Token _head;
  Token _last;

  Tokenizer(this.text);

  Token tokenize() {
    _emit(null);

    for (int i = 0; i < text.length; i++) {
      String c = text[i];

      if (whitespace.contains(c)) {
        // skip
      } else if (c == '/' && _peek(i) == '/') {
        int index = text.indexOf('\n', i);
        if (index == -1) index = text.length;
        _emit(text.substring(i, index));
        i = index;
      } else if (alphaNum.contains(c)) {
        int start = i;

        while (alphaNum.contains(_peek(i))) {
          i++;
        }

        _emit(text.substring(start, i + 1));
      } else {
        _emit(c);
      }
    }

    _emit(null);

    _head = _head.next;

    return _head;
  }

  void _emit(String value) {
    Token token = new Token(value);
    if (_head == null) _head = token;
    if (_last != null) _last.next = token;
    _last = token;
  }

  String _peek(int i) {
    i += 1;
    return i < text.length ? text[i] :new String.fromCharCodes([0]);
  }

  String toString() {
    StringBuffer buf = new StringBuffer();

    Token t = _head;

    buf.write('[${t}]\n');

    while (!t.eof) {
      t = t.next;
      buf.write('[${t}]\n');
    }

    return buf.toString().trim();
  }
}

abstract class Parser {
  final Token startToken;

  Token current;

  Parser(this.startToken);

  Token expect(String text) {
    Token t = advance();
    if (text != t.text) fail('expected ${text}, got ${t}');
    return t;
  }

  bool consume(String text) {
    if (peek().text == text) {
      advance();
      return true;
    } else {
      return false;
    }
  }

  Token peek() => current.eof ? current : current.next;

  Token expectName() {
    Token t = advance();
    if (!t.isName) fail('expected name token');
    return t;
  }

  Token advance() {
    if (current == null) {
      current = startToken;
    } else if (!current.eof) {
      current = current.next;
    }

    return current;
  }

  String collectComments() {
    StringBuffer buf = new StringBuffer();

    while (peek().isComment) {
      Token t = advance();
      String str = t.text.substring(2);
      buf.write(' ${str}');
    }

    if (buf.isEmpty) return null;
    return collapseWhitespace(buf.toString()).trim();
  }

  void validate(bool result, String message) {
    if (!result) throw 'expected ${message}';
  }

  void fail(String message) => throw message;
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
