# dartlang plugin changelog

## unreleased
- added a setting to enable the debugger; it is disabled by default while we
  work to complete it
- added the ability to copy text from the console and errors views
- we now remember launch configurations and breakpoints between sessions

## 0.4.13
- exposed quick assists - `ctrl-1`; these are common source refactorings
- tweaked the css for the dartdoc tooltip
- tweaked the display of debugger variables
- fixed a NPE when listening for file changes (#458)
- improved the error messages and progress display when performing a rename
  refactoring
- we now save all files before running an application
- improved the algorithm to determine which app to run on a `cmd-R`
- when opening a directory with multiple projects, we now notify if pub needs to
  be run for each project
- fixed a regression with jump-to-declaration
- fixed syntax highlighting issues with dartdoc comments

## 0.4.12
- fixed an issue when editing in c-style comments
- we now log fatal analysis server errors (this should be useful in diagnosing
  issues when they happen)
- added syntax highlighting for `.analysis_options` files
- fixed issues with having the same file open in multiple editors
- we now show analysis information for more Dart files (for package: files, as
  well as files in the user's project)

## 0.4.11
- fixed an issue when running `pub get` in a directory without a pubspec.yaml
- adjusted the highlighting in the outline view
- fixed an issue with restoring atom preferences
- switched to using the `flutter` command to launch flutter apps, instead of the
  `sky_tool` script

## 0.4.10
- improved the UI for running Pub commands and applications
- fixed an issue when traversing new projects on Windows
- check for new versions of the `sky_tools` package when creating Flutter apps
- improved error handling when trying to create projects and no Dart SDK is available
- auto hide and show the errors view when running applications
- super-mixins - DEP 34 - now defaults to on
- added code to check for and warn when `pub get` should be run on a project
- improved the ability for the pub get and pub update commands to select the
  correct pubspec.yaml file to operate on
- updated some references from `sky_tools` to `flutter`

## 0.4.9
- added UI to improve discoverability for quick fixes (`ctrl-1` / `alt-enter`)
- improved launching for Flutter apps
- improved UX of the console view

## 0.4.8
- added the ability to launch Dart command-line apps (cmd-R / ctrl-R)
- the `run flutter application` is now just `run application` - it automatically
  determines the application type to run
- changed the outline view style _back_ to using much of the syntax highlighting
  from the current editor theme (at 0.75 opacity)
- added a setting to enable analysis for DEP 34 - less restricted mixins
- fixed an issue with the `linter` plugin where info level issues were named `Trace`
- fixed an style / clipping issue in the problems view
- new and updated keybindings! Why the changes? So many, many conflicts on
  various platforms. The latest is: `f4` is `type hierarchy`, `ctrl-f4` (or
  `cmd-f4`) is `find references`, and `ctrl-alt-down` (or `alt-cmd-down`) is
  `jump to declaration`.

## 0.4.7
- filtered 'potential' edits from rename refactorings
- improved the UI for the for the rename refactoring confirmation dialog
- turned off the `core.followSymlinks` preference by default
- bumped the minimum recommended SDK version to 1.12.0
- changed to check for an `.analysis_options` file when looking for Dart projects
- made the notification for the analysis server shutting down less scary
- added a `return-from-declaration` (alt-cmd-up) command to jump back from a
  jump to declaration operation

## 0.4.6
- improved logging when receiving errors from the analysis server
- changed to displaying 'todo' issues to default to off
- changed to terminating the flutter server when launching a new app
- items in the type hierarchy are now sorted lexically

## 0.4.5
- fixed an issue where we didn't dispose of the errors view on plugin shutdown
- changed the styling of the outline view to be less distracting
- fixed an issue with jerkiness when dragging the size of the outline view
- change to have the errors view better respect the user settings
- added a close button to the outline view

## 0.4.4
- added an issue count to the problems view
- added a console view to display stdout from launched applications
- added a status line contribution to track launched applications
- running a Sky app now pipes the stdout back to the console view
- revamped the UI of the outline view
- iterated on the console UI
- added a button on sky launches to open a browser page on the Observatory
- pre-filled in the 'Send Feedback' form with version and OS information
- fixed an issue with the wrong editor being selected after a multi-file rename
  refactoring
- added a 'show sdk info' command and dialog

## 0.4.3
- improved the UI for user executed discrete tasks (pub get, pub upgrade, ...)
- fixed running sky apps (the `run sky application` command)
- added a key binding for `run sky application` - `cmd-r`
- added a `Settings…` menu item to the Dart package menu
- sorted results in the `Find References` view by file location
- the views on the right-hand side - type hierarchy and find references - are
  now mutually exclusive
- wrote a new getting started guide: https://dart-atom.github.io/dartlang/

## 0.4.2
- fixed an exception from the outline view when viewing empty Dart files
- removed the setting to filter 'When compiled to JS' warnings
- made the dependency on the `linter` package optional

## 0.4.1
- added a fancy new errors view
- added an outline view for Dart files
- fixed an issue with context menus not being enabled for some items
- make `info` level analysis issues more visible in the editor

## 0.4.0
- improved the notifications when we're unable to find a Dart SDK
- more work towards reducing code completion twitchiness
- don't show the release notes at startup; they are now available from the
  `Packages > Dart > Release Notes` menu item
- added usage reporting via Google Analytics

## 0.3.17
- added a `Packages > Dart > Release Notes` menu item
- added a `Packages > Dart > Getting Started` menu item
- adjusted the default delay for code completion to be less aggressive
- `pub run` and `pub global run` now available from the context menu
- added a `--no-package-symlinks` option for use by `pub get` and `pub update`
- the 'Find References' view now shows the element name that was searched for

## 0.3.16
- changed the quick fix keybinding on the mac from `cmd-1` to `ctrl-1`
- added the ability to run Sky applications (right click, Run Sky Application)
- improved the UI for long running tasks
- improved the feedback for long running requests into the analysis server

## 0.3.15
- fixed an exception when opening a context menu
- added the ability to sort directives (right click in a dart editor and
  choose `Organize Directives`, or `ctrl-alt-o`)
- added a warning when the `emmet` package is installed (it causes editing
  performance issues in Dart files)

## 0.3.14
- added the ability to create a new Sky project. This is available from the
  `create sky project` command or via the `Packages > Dart` menu item
- added a `pub get` and `pub upgrade` context menu off project directories in
  the tree view
- added code to better recognize when the analysis server terminates
- added the ability to sort file members (right click in a dart editor and
  choose `Sort Members`)

## 0.3.12
- fixed an issue with code completing empty import statements
- items in the type hierarchy and find references views are now collapsable
- removed Atom's default lexical completer from line and dartdoc comments
- implemented support for multiple quick-fixes (cmd-1 / ctrl-1)
- added a setting to start the analysis server with diagnostics on. Once enabled,
  restart atom and view the diagnostics via the 'analysis server status' command

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
