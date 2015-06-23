# dart-lang-experimental

An experimental Dart plugin for Atom.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/dart-atom/dart-lang-experimental/issues

## Plugins we depend on

You'll need to install the `linter` plugin in order to have analysis errors and
warnings show up.

## Developing

To work on `dart-lang-experimental`:

- install [Atom](https://atom.io/)
- clone this repo
- from the command line, run `pub get`
- from the command line, run `grind build`; this will re-compile the javascript
- from the repo directory, type `apm link` (you can install `apm` via the
  `Atom > Install Shell Commands` menu item)
- re-start Atom

The plugin will be active in your copy of Atom. When making changes:

- `type type type...`

and either:

- from atom, hit `ctrl-option-command-;`; this will re-build the dart code and re-start atom

or:

- run `grind build`
- from atom, hit `ctrl-option-command-l`; this will re-start atom
