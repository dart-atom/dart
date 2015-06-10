# atom-dartlang-experimental

An experimental Dart plugin for Atom.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/dart-lang/atom-dartlang-experimental/issues

## Developing

To work on `atom-dartlang-experimental`:

- install [Atom](https://atom.io/)
- clone this repo
- from the command line, run `grind build`; this will re-compile the javascript
- from the repo directory, type `apm link` (you can install `apm` via the
  `Atom > Install Shell Commands` menu item)
- re-start Atom

The plugin will be active in your copy of Atom. When making changes:

- `type type type...`
- run `grind build`
- from atom, hit `ctrl-option-command-l`; this will re-start atom
