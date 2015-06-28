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

// TODO: write a tokenizer

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

class Api {
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

class Method {
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

class Type {
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

class Enum {
  final String name;
  final String docs;

  Enum(this.name, String definition, [this.docs]) {

  }

  void generate(DartGenerator gen) {
    gen.writeln();
    if (docs != null) {
      gen.writeDocs(docs);
      gen.writeStatement('enum ${name} {');
      gen.writeln('foo');
      gen.writeStatement('}');
    }
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
