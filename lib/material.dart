import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import 'elements.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.material');

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

  MTab(this.id, this.name) : _tabElement = div(c: 'material-tab'), content = div() {
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
typedef int ListSort<T>(T obj1, T obj2);

// TODO: use cmd, ctrl to toggle list items

class MList<T extends MItem> extends CoreElement {
  final ListRenderer renderer;
  final ListSort<T> sort;
  final ListFilter filter;

  final Property<T> selectedItem = new Property();

  CoreElement _ul;
  Map<String, Pair<T, CoreElement>> _itemKeyToElement = {};

  StreamController<T> _singleClick = new StreamController.broadcast();
  StreamController<T> _doubleClick = new StreamController.broadcast();

  MList(this.renderer, {this.sort, this.filter}) : super('div', classes: 'material-list') {
    layoutVertical();
    add([
      _ul = ul()..flex()
    ]);
    click(() => selectItem(null));
  }

  Future update(List<T> modelObjects, {bool refreshSelection: false}) {
    if (filter != null || sort != null) {
      if (filter != null) {
        modelObjects = modelObjects.where((o) => !filter(o)).toList();
      } else {
        modelObjects = modelObjects.toList();
      }

      if (sort != null) modelObjects.sort(sort);
    }

    String _selKey = selectedItem.value?.key;

    CoreElement _newUl = ul()..flex();
    _itemKeyToElement.clear();
    return _populateChildren('', modelObjects, _newUl).whenComplete(() {
      _ul.element.children = _newUl.element.children;
      if (refreshSelection) {
        if (_itemKeyToElement[_selKey] != null) {
          CoreElement e = _itemKeyToElement[_selKey].right;
          e.toggleClass('material-list-selected', true);
          selectedItem.value = _itemKeyToElement[_selKey].left;
        } else if (selectedItem.value != null){
          selectedItem.value = null;
        }
      }
    });
  }

  void selectItem(T item) {
    if (selectedItem.value != null) {
      CoreElement oldSelected = _itemKeyToElement[selectedItem.value.key].right;
      if (oldSelected != null) {
        oldSelected.toggleClass('material-list-selected', false);
      }
    }
    CoreElement element = _itemKeyToElement[item?.key]?.right;
    if (element == null) item = null;
    selectedItem.value = item;
    if (element != null) {
      element.toggleClass('material-list-selected', true);
    }
  }

  Future _populateChildren(String root, List<T> modelObjects, CoreElement container) {
    List<Future> futures = [];
    for (T item in modelObjects) {
      CoreElement element = container.add(li());
      String key = '$root/${item.id}';
      try {
        futures.add(_render(key, item, element));
      } catch (e, st) {
        print('${e}: ${st}');
      }

      item.key = key;
      _itemKeyToElement[key] = new Pair(item, element);

      element.click(() {
        selectItem(item);
        _singleClick.add(item);
      });

      element.dblclick(() {
        _doubleClick.add(item);
      });
    }
    return Future.wait(futures);
  }

  Future _render(String id, T item, CoreElement element) {
    renderer(item, element);
    return new Future.value();
  }

  Stream<T> get onSingleClick => _singleClick.stream;
  Stream<T> get onDoubleClick => _doubleClick.stream;
}

abstract class TreeModel<T> {
  bool canHaveChildren(T obj);
  Future<List<T>> getChildren(T obj);
}

class MTree<T extends MItem> extends MList<T> {
  final TreeModel<T> treeModel;

  final Set<String> expandedNodes = new Set();

  MTree(this.treeModel, ListRenderer renderer, {ListFilter filter}) :
      super(renderer, filter: filter);

  Future _render(String id, T item, CoreElement element) {
    List<Future> futures = [];
    if (treeModel.canHaveChildren(item)) {
      CoreElement expansionTriangle;
      CoreElement childContainer;

      element.add(
        expansionTriangle = span(c: 'icon-triangle-right')
      );

      var toggleExpand = () {
        expansionTriangle.toggleClass('icon-triangle-right');
        expansionTriangle.toggleClass('icon-triangle-down');

        if (childContainer == null) {
          childContainer = ul(c: 'material-list-indent');
          int index = element.element.parent.children.indexOf(element.element);
          element.element.parent.children.insert(index + 1, childContainer.element);
          expandedNodes.add(id);
          // TODO: Show feedback during an expansion.
          return treeModel.getChildren(item).then((List<T> items) {
            return _populateChildren(id, items, childContainer);
          }).catchError((e, st) {
            atom.notifications.addError('${e}');
            _logger.info('unable to expand child', e, st);
          });
        } else {
          bool isHidden = !childContainer.hasAttribute('hidden');
          if (isHidden) {
            expandedNodes.remove(id);
          } else {
            expandedNodes.add(id);
          }
          childContainer.hidden(isHidden);
          if (!childContainer.hasAttribute('hidden')) {
            _makeFirstChildVisible(childContainer);
          }
          return new Future.value();
        }
      };

      element.dblclick(toggleExpand);
      expansionTriangle.click(toggleExpand);

      if (expandedNodes.contains(id)) futures.add(toggleExpand());
    } else {
      element.add(
        span(c: 'icon-triangle-right visibility-hidden')
      );
    }

    futures.add(super._render(id, item, element));

    return Future.wait(futures);
  }

  void _makeFirstChildVisible(CoreElement element) {
    List children = element.element.children;
    if (children.isNotEmpty) children.first.scrollIntoView();
  }
}
