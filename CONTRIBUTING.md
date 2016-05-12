First up, please join our [dart-atom-dev mailing list][list].

Contributions welcome! You can help out by testing and filing issues, helping with docs, or writing code.

## Developing the plugin
To work on `dartlang` plugin:

- install [Atom](https://atom.io/)
- clone this repo
- from the command line, run `pub get`
- to use `grind` :
  - from the command line, run `pub global activate grinder`
  - then run `grind build`; this will re-compile the javascript
- from the repo directory, type `apm link` (you can install `apm` via the
  `Atom > Install Shell Commands` menu item)
- restart Atom

The plugin will be active in your copy of Atom. When making changes:

- `type type type...`

and:

- run `grind build`
- from atom, hit `ctrl-option-command-l`; this will re-start atom

## Publishing a new release

- `git pull` the latest
- rev the changelog version from 'unreleased' to the next version
- rev the pubspec version to the same
- commit, push to master
- verify that the package.json version is one minor patch older; apm will rev the last number - we want that to match the changelog and pubspec versions
- from the CLI: `apm publish patch`
- Tweet announcement via @dartpluginatom

## Docs

Some of our docs are in the main readme.md file. We try and keep that file short and sweet.

Most of our docs are in the `gh-pages` branch on the repo. We author the docs in markdown, and github's gh-pages system automatically converts it the html (we're using the 'SinglePaged' jekyll template). Changes pushed to the `gh-pages` branch go live automatically. When working on the docs, run `jekyll serve -w --force_polling` to see a preview version of the rendered docs.

[list]: https://groups.google.com/forum/#!forum/dart-atom-dev
