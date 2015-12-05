import 'dart:async';

import 'elements.dart';
import 'utils.dart';

class MIconButton extends CoreElement {
  final String iconName;

  MIconButton(this.iconName) : super('div', classes: 'material-icon-button') {
    add([
      span(c: iconName)
    ]);
  }
}

class MTabGroup extends CoreElement {
  final SelectionGroup<MTab> tabs = new SelectionGroup();

  CoreElement _tabContainer;
  CoreElement _contentContainer;

  MTab _activeTab;

  MTabGroup() : super('div', classes: 'material-tabgroup') {
    layoutVertical();

    add([
      _tabContainer = div(c: 'material-tab-container'),
      _contentContainer = div()..layoutVertical()..flex()
    ]);

    tabs.onAdded.listen(_handleTabAdd);
    tabs.onSelectionChanged.listen(_handleTabActivate);
  }

  void _handleTabAdd(MTab tab) {
    _tabContainer.add(tab._tabElement.element);
    _contentContainer.add(tab.content);
    tab.content.hidden(true);

    tab._tabElement.click(() => tabs.setSelection(tab));
  }

  void _handleTabActivate(MTab tab) {
    if (_activeTab == tab) return;

    // Deactivate _activeTab.
    if (_activeTab != null) {
      _activeTab.content.hidden(true);
      _activeTab._tabElement.toggleClass('tab-selected', false);
      _activeTab.active.value = false;
    }

    _activeTab = tab;

    // Activate tab.
    if (_activeTab != null) {
      _activeTab.content.hidden(false);
      _activeTab._tabElement.toggleClass('tab-selected', true);
      _activeTab._tabElement.element.scrollIntoView();
      _activeTab.active.value = true;
    }
  }

  bool hasTabId(String id) {
    return tabs.items.any((tab) => tab.id == id);
  }

  void activateTabId(String id) {
    for (MTab tab in tabs.items) {
      if (tab.id == id) tabs.setSelection(tab);
    }
  }
}

abstract class MTab implements Disposable {
  final String id;
  final String name;
  final CoreElement _tabElement;
  final CoreElement content;
  final Property<bool> enabled = new Property(true);
  final Property<bool> active = new Property(true);

  MTab(this.id, this.name) :
      _tabElement = div(c: 'material-tab'),
      content = div() {
    _tabElement.text = name;
    enabled.onChanged.listen((val) {
      _tabElement.enabled = val;
    });
  }

  void dispose();

  String toString() => '$id $name';
}

typedef void ListRenderer(dynamic obj, CoreElement element);
typedef bool ListFilter(dynamic obj);
typedef int ListSort(dynamic obj1, dynamic obj2);

// TODO: use cmd, ctrl to toggle list items

class MList<T> extends CoreElement {
  final ListRenderer renderer;
  final ListSort sort;
  final ListFilter filter;

  final Property<T> selectedItem = new Property();

  CoreElement _ul;
  Map<T, CoreElement> _itemToElement = {};

  StreamController<T> _doubleClick = new StreamController.broadcast();

  MList(this.renderer, {this.sort, this.filter}) : super('div', classes: 'material-list') {
    layoutVertical();
    add([
      _ul = ul()..flex()
    ]);
    click(() => selectItem(null));
  }

  void update(List<T> modelObjects) {
    if (filter != null || sort != null) {
      if (filter != null) {
        modelObjects = modelObjects.where((o) => !filter(o)).toList();
      } else {
        modelObjects = modelObjects.toList();
      }

      if (sort != null) modelObjects.sort(sort);
    }

    // TODO: optimize this
    _ul.clear();
    _itemToElement.clear();

    T _sel = selectedItem.value;

    for (T item in modelObjects) {
      CoreElement element = _ul.add(li());

      renderer(item, element);
      _itemToElement[item] = element;

      element.click(() {
        selectItem(item);
      });

      element.dblclick(() {
        _doubleClick.add(item);
      });

      if (_sel == item) {
        element.toggleClass('material-list-selected', true);
      }
    }
  }

  void selectItem(T item) {
    if (selectedItem.value != null) {
      CoreElement oldSelected = _itemToElement[selectedItem.value];
      if (oldSelected != null) {
        oldSelected.toggleClass('material-list-selected', false);
      }
    }

    CoreElement element = _itemToElement[item];
    if (element == null) item = null;
    selectedItem.value = item;
    if (element != null) {
      element.toggleClass('material-list-selected', true);
    }
  }

  Stream<T> get onDoubleClick => _doubleClick.stream;
}
