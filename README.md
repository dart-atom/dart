# Dart plugin for Atom

A [Dart](https://www.dartlang.org) plugin for [Atom](https://atom.io).

[![Build Status](https://travis-ci.org/dart-atom/dartlang.svg)](https://travis-ci.org/dart-atom/dartlang)

![Screenshot of Dart plugin in Atom](https://raw.githubusercontent.com/dart-atom/dartlang/master/screenshot.png)

## Installing

- install [Atom](https://atom.io/)
- install the [linter][] package
- install this [dartlang][] package
- (potentially) configure the location of your Dart SDK

The plugin should auto-detect the Dart SDK location. If not, you can set it
manually in the plugin configuration page (`Preferences > Packages > dartlang`).

### Optional packages

We also recommend the following (optional) packages:

- [last-cursor-position](https://atom.io/packages/last-cursor-position): helps you
  move between cursor location history (useful when using "jump to definition")

## Features

- auto-discovery of Dart SDK location
- syntax highlighting
- as-you-type errors and warnings
- code completion
- `F1` to see dartdocs
- `F3` (or option-click) to jump to definition
- `F4` to see a type hierarchy
- find references to classes and methods
- rename refactoring
- pub commands (get and update) are available via context menus
- view type hierarchy
- format source code with `dartfmt` (use the Command Palette)

A lot of Atom's functionality is surfaced via named commands. You can see all
the available commands by hitting `shift-command-p`.

To view detailed info about what the analysis server is doing, run the
`analysis server status` command.

## Sending feedback

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/atom-dart/dartlang/issues

## Developing the plugin

Check out [how to develop][develop].

## Logging

You can change the logging level for the plugin in the config file. Go to
`Atom > Open Your Config` and find the `dartlang` section. Add a
line for `logging`, and set it to a value like `info`, `fine`, `all`, or `none`.
All the values from the `logging` pub package are legal. The log messages will
show up in the devtools console for Atom (`View > Developer > Toggle Developer Tools`).

## License

See the [LICENSE](https://github.com/dart-atom/dartlang/blob/master/LICENSE) file.

[linter]: https://atom.io/packages/linter
[develop]: https://github.com/dart-atom/dartlang/wiki/Developing
[dartlang]: https://atom.io/packages/dartlang
