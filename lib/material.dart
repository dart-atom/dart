
import 'elements.dart';

class MIconButton extends CoreElement {
  final String iconName;

  MIconButton(this.iconName) : super('div', classes: 'material-icon-button') {
    // TODO:
    add([
      span(c: iconName)
    ]);
  }
}

// TODO:

class MTabGroup {

}

// TODO:

class MTab {

}
