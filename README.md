# Dart plugin for Atom

An experimental [Dart](https://www.dartlang.org) plugin for [Atom](https://atom.io).

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/atom-dart/dartlang/issues

## Plugins we depend on

You'll need to install the `linter` plugin in order to have analysis errors and
warnings show up.

## Installing and running the plugin

- install [Atom](https://atom.io/)
- clone this repo
- from the command line, run `pub get`
- then, run `apm link` (you can install `apm` via the `Atom > Install Shell Commands` menu item)
- re-start Atom

The plugin _should_ auto detect the Dart SDK location. If not, you can set it
manually in the plugin configuration page (Preferences > Packages >
dart-lang-experimental).

You'll get errors and warnings on file save. You can see dartdoc documentation
for an element by hitting `F1`. To jump to an element's declaration, hit `F3` or
option-click on a symbol name. The UI for the dartdoc help is _very_ provisional.

The pub commands (get and update) are available via context menus.

A lot of Atom's functionality is surfaced via named commands. You can see all
the available commands by hitting `shift-command-p`.

We sometimes don't properly recognize newly created projects as Dart projects.
You can either run the `refresh dart projects` command, or restart Atom.

To view detailed info about what the analysis server is doing, run the
`analysis server status` command.

There are a lot of cool plugins written for Atom; it's worth poking around the
[packages page](https://atom.io/packages) to see what's out there.

## Developing the plugin

To work on `dartlang` plugin:

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

## Logging

You can change the logging level for the plugin in the config file. Go to
`Atom > Open Your Config` and find the `dartlang` section. Add a
line for `logging`, and set it to a value like `info`, `fine`, `all`, or `none`.
All the values from the `logging` pub package are legal. The log messages will
show up in the devtools console for Atom (`View > Developer > Toggle Developer Tools`).
