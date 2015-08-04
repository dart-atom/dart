# Changelog

## 0.3.11
- added a check to ensure the the Dart SDK meets a minimum required version
- added code to trap an exception from the analysis server (`setPriorityFiles`)
- fixed an issue with code completion and `import` statements

## 0.3.10
- fixed an exception when used with the 1.3.0 version of the `linter` package

## 0.3.9
- fixed exceptions in the find references feature
- added a key binding for `dartlang:find-references` (ctrl-shift-g / shift-cmd-g)
- added a key binding for `dartlang:refactor-rename` alt-shift-r

## 0.3.8
- added the ability to run `pub run` and `pub global run` applications
- added a `pub global activate` command
- sorted the preferences from ~most to least important
- tweaked the display of the `Find References` view
- fixed an issue where upgrading the plugin (or disabling and re-enabling it)
  would leave a status-bar contribution behind

## 0.3.7
- implemented a type hierarchy view (F4)
- implemented a find references view (available from the context menu)
- exposed the rename refactoring as a context menu item
- we now display new plugin features after an upgrade

## 0.3.6
- added an option to format on save
- we now warn when packages that we require are not installed
- fixed an NPE from the `re-analyze sources` command
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
