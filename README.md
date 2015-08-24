# Dart plugin for Atom

A [Dart](https://www.dartlang.org) plugin for [Atom](https://atom.io).

[![Build Status](https://travis-ci.org/dart-atom/dartlang.svg)](https://travis-ci.org/dart-atom/dartlang)

![Screenshot of Dart plugin in Atom](https://raw.githubusercontent.com/dart-atom/dartlang/master/doc/images/screenshot.png)

## What is it?

This package is a full-featured Dart development plugin for Atom. It supports
features like auto-discovery of the Dart SDK, errors and warnings shown as you
type, code completion, refactorings, and integration with Pub and other tools.

## Installing

- install [Atom](https://atom.io/)
- install the [linter][] package (with `apm install linter` or through the
  Atom UI)
- install this [dartlang][] package (with `apm install dartlang` or through the
  Atom UI)

The plugin should auto-detect the Dart SDK location. If not, you can set it
manually in the plugin configuration page (`Preferences > Packages > dartlang`).

### Optional packages

We recommend the following (optional) packages:

- [last-cursor-position](https://atom.io/packages/last-cursor-position) helps you
move between cursor location history (useful when using "jump to definition").
- [minimap](https://atom.io/packages/minimap) adds a small preview window of the
full source code of a file.
- [minimap-find-and-replace](https://atom.io/packages/minimap-find-and-replace)
displays the search matches in the minimap.

### Packages to avoid

We do not recommend using both [emmet](https://atom.io/packages/emmet) and the
dartlang package together. For an unknown reason, editing large `.dart` files
slows down if you have the emmet plugin installed. We have filed an
[issue](https://github.com/emmetio/emmet-atom/issues/319).

## Getting started

See our
[getting started](https://github.com/dart-atom/dartlang/blob/master/doc/getting_started.md)
guide for a walkthrough of how to use all the Dart features. This is useful for
users new to the plugin and users new to Atom.

## Sending feedback

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/dart-atom/dartlang/issues

## License

See the [LICENSE](https://github.com/dart-atom/dartlang/blob/master/LICENSE)
file.

[linter]: https://atom.io/packages/linter
[develop]: https://github.com/dart-atom/dartlang/wiki/Developing
[dartlang]: https://atom.io/packages/dartlang
