// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.elements;

import 'dart:async';
import 'dart:html';

/// Finds the first descendant element of this document with the given id.
Element queryId(String id) => querySelector('#${id}');

/// Finds the first descendant element of this document with the given id.
Element $(String id) => querySelector('#${id}');

// TODO: We should convert this library to something closer to a DSL for html.

class CoreElement {
  final Element element;

  // JsObject _proxy;
  // Map<String, Stream> _eventStreams = {};

  CoreElement.from(this.element);

  CoreElement(String tag, {String text}) : element = new Element.tag(tag) {
    if (text != null) element.text = text;
  }

  CoreElement.div([String text]) : this('div', text:text);
  CoreElement.li() : this('li');
  CoreElement.p([String text]) : this('p', text: text);
  CoreElement.section() : this('section');
  CoreElement.span([String text]) : this('span', text: text);

  String get tag => element.tagName;

  String get id => attribute('id');
  set id(String value) => setAttribute('id', value);

  bool hasAttribute(String name) => element.attributes.containsKey(name);

  void toggleAttribute(String name, [bool value]) {
    if (value == null) value = !element.attributes.containsKey(name);

    if (value) {
      element.setAttribute(name, '');
    } else {
      element.attributes.remove(name);
    }
  }

  String attribute(String name) => element.getAttribute(name);

  void setAttribute(String name, [String value = '']) =>
      element.setAttribute(name, value);

  String clearAttribute(String name) => element.attributes.remove(name);

  void clazz(String _class) {
    if (_class.contains(' ')) {
      throw new ArgumentError('spaces not allowed in class names');
    }
    element.classes.add(_class);
  }

  void toggleClass(String name, [bool value]) {
    element.classes.toggle(name, value);
  }

  set text(String value) {
    element.text = value;
  }

  // Atom classes.
  void block() => clazz('block');
  void inlineBlock() => clazz('inline-block');
  void inlineBlockTight() => clazz('inline-block-tight');

  /// Add the given child to this element's list of children. [child] must be
  /// either a `CoreElement` or an `Element`.
  dynamic add(dynamic child) {
    if (child is CoreElement) {
      element.children.add(child.element);
    } else if (child is Element) {
      element.children.add(child);
    } else {
      throw new ArgumentError('child must be a CoreElement or an Element');
    }
    return child;
  }

  void hidden([bool value]) => toggleAttribute('hidden', value);

  String get icon => attribute('icon');
  set icon(String value) => setAttribute('icon', value);

  String get label => attribute('label');
  set label(String value) => setAttribute('label', value);

  bool get disabled => hasAttribute('disabled');
  set disabled(bool value) => toggleAttribute('disabled', value);

  // Layout types.
  void layout() => toggleAttribute('layout');
  void horizontal() => toggleAttribute('horizontal');
  void vertical() => toggleAttribute('vertical');

  void layoutHorizontal() {
    setAttribute('layout');
    setAttribute('horizontal');
  }

  void layoutVertical() {
    setAttribute('layout');
    setAttribute('vertical');
  }

  // Layout params.
  void fit() => toggleAttribute('fit');
  void flex([int flexAmount]) {
    toggleAttribute('flex', true);

    if (flexAmount != null) {
      if (flexAmount == 1) toggleAttribute('one', true);
      else if (flexAmount == 2) toggleAttribute('two', true);
      else if (flexAmount == 3) toggleAttribute('three', true);
      else if (flexAmount == 4) toggleAttribute('four', true);
      else if (flexAmount == 5) toggleAttribute('five', true);
    }
  }

  Stream<Event> get onClick => element.onClick;

  // dynamic call(String methodName, [List args]) {
  //   if (_proxy == null) _proxy = new JsObject.fromBrowserObject(element);
  //   return _proxy.callMethod(methodName, args);
  // }

  // dynamic property(String name) {
  //   if (_proxy == null) _proxy = new JsObject.fromBrowserObject(element);
  //   return _proxy[name];
  // }

  // Stream listen(String eventName, {Function converter, bool sync: false}) {
  //   if (!_eventStreams.containsKey(eventName)) {
  //     StreamController controller = new StreamController.broadcast(sync: sync);
  //     _eventStreams[eventName] = controller.stream;
  //     element.on[eventName].listen((e) {
  //       controller.add(converter == null ? e : converter(e));
  //     });
  //   }
  //
  //   return _eventStreams[eventName];
  // }

  void dispose() {
    if (element.parent == null) return;

    if (element.parent.children.contains(element)) {
      try {
        element.parent.children.remove(element);
      } catch (e) {
      }
    }
  }

  String toString() => element.toString();
}

// <div class='block'>
//   <progress class='inline-block' />
//   <span class='inline-block'>Indeterminate</span>
// </div>
class ProgressElement extends CoreElement {
  CoreElement _progress;

  ProgressElement() : super.div() {
    block();
    _progress = add(new CoreElement('progress')..inlineBlock());
  }

  set value(int val) => _progress.setAttribute('value', val.toString());
  set max(int val) => _progress.setAttribute('max', val.toString());
}
