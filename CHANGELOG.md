# Changelog

## 0.3.7
- implement a type hierarchy view (F4)
- implement a find references view (available from the context menu)
- expose the rename refactoring as a context menu item
- display new plugin features after an upgrade

## 0.3.6
- add an option to format on save
- warn when packages that we require are not installed
- fix an NPE from the `re-analyze sources` command
- added a close button to the jobs dialog and the analysis server dialog

## 0.3.5
- send the analysis server fewer notifications of changed files
- only send the analysis server change notifications for files in Dart projects

## 0.3.4
- minor release to address a performance issue

## 0.3.3
- improved the UI of the dartdoc modal window (`F1`)
- fixes to code completion
- added support for null aware operators
- fixed some auto-indent issues
- added a per file and per project cap to the number of reported issues
- fixed inconsistent syntax highlighting between setters and getters

## 0.3.2
- fixed an issue with stopping and re-starting the analysis server
- exposed the `dartfmt` tool as a context menu item
- guard against watching synthetic project directories (like the `config` dir)
- adjusted keybindings for windows

## 0.3.1
- improved editing for dartdoc comments and improved the auto-indent behavior
- added the ability to filter out certain analysis warnings

## 0.3.0
- fixes for jump to declaration
- fixes for the offset location of some errors and warnings
- added a `Send Feedback` menu item

## 0.2.0
- first published version
- initial integration with the analysis server
- code completion, errors and warnings, and jump to declaration implemented

## 0.0.1
- initial version
