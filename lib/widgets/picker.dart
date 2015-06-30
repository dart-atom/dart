library widgets.picker;

import 'dart:async';
import 'dart:js';
import 'dart:html';

import '../atom.dart';

/*
  <atom-panel class='modal'>      
      <div class='select-list'>
          <atom-text-editor mini>I searched for this</atom-text-editor>
          <div class='error-message'>Nothing has been found!</div>
      </div>
  </atom-panel>  
 */
class PickerElement extends HtmlElement {
  PickerElement.created() : super.created() {    
    assemble();
  }

  static register() {
    document.registerElement('picker-element', PickerElement);
  }

  static showPicker() {
    var element = new Element.tag('picker-element');
    var _panel = atom.workspace.addModalPanel(item: element);
    atom.commands.add('atom-workspace', 'core:cancel', (_) {
      _panel.destroy();
    });
  }
  
  assemble() {
    t('atom-panel', {'class': 'modal'}, [
      t('div', {'class': 'select-list'}, [
        t('atom-text-editor', {'mini': true}),
        t('div', {}, 'Nothing has been found!')
      ])
    ]);    
  }
}


Element t(String tag, Map attrs, [content]) {
  print('Did this work?');
  var element = new Element.tag(tag);
  print('I now have $element; it is ${element.runtimeType}');
  print('It has ${element.attributes}');
  
  if (element is JsObject) {
    print('Found the winner');
  } else {
    element.attributes.addAll(attrs);
  }
  print('I have called with $attrs');
  if (content is List) {
    content.forEach(element.append);
  } else if (content is String) {
    element.appendText(content);
  } else if (content is Node) {
    element.append(content);
  }
  return element;
  
}