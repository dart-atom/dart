---
title: "Getting Started"
bg: blue  
color: white   
fa-icon: sign-in
---

## Using commands

Much of Atom's functionality is surfaced via named commands. You can see all the
available commands by hitting `shift-cmd-p`. You can execute a command directly by
searching for it and selecting it in the command palette. Many commands can also
be accessed using associated key bindings.

## Setting up and configuring

To open the settings for Atom, hit `cmd-,` or select the `Atom > Preferences…`
menu item. From here you can configure general text editor settings, customize
key bindings, customize the theme and look of Atom, and adjust settings for
various Atom packages, including the `dartlang` package.

<img src="img/settings.png" width="40%" class="img-centered"/>

The `dartlang` plugin will attempt to auto-locate the Dart SDK. If it fails, you
can adjust your operating system's `PATH` settings and manually run the SDK
auto-locate command (`'auto locate sdk'`). Or, you can configure the SDK's path
in `dartlang` settings section.

In addition, the `autocomplete-plus` plugin has settings that are useful to
customize. This plugin controls the UI of the code completion popup. From its
preference page you can control how frequently autocomplete comes up, which keys
invoke it, and which keys choose from selections.

<img src="img/autocomplete.png" width="65%" class="img-centered"/>

## Opening Dart projects

To open a project, use the `'add project folder'` command, or select the
`File > Add Project Folder…` menu item. When a project is added to Atom, the
`dartlang` plugin will recursively scan through the project, two directory levels
deep, looking for Dart projects. These are directories with `pubspec.yaml` or
`.packages` files.

When there are any Dart projects open in Atom, the `dartlang` plugin will
automatically start the Dart analysis server. This is an external process that
provides functionality like analyzing code for errors and warnings, providing
code completion information, and various code searching and refactoring tools.
This process is automatically managed by the `dartlang` plugin.

## Working with Dart projects

There are various tools and commands available to help you work with Dart
projects. The various `pub` commands are available as context menu items in the
files view. The commands are also available from the command palette
(`shift-cmd-p`). So, to run `pub get` on a project, select the `pubspec.yaml` file
in the files view, right click, and select the `Pub Get` menu item. Alternatively,
whenever a Dart file is open, you can run the `pub get` Atom command, and pub
will be run for the associated Dart project.

Other Pub commands which are available are `pub activate`, to install various
Dart tools. `pub global run`, which lets you execute a previously installed pub
application. And `pub run`, which lets you execute a pub app installed locally to
that project (referenced from the pubspec).

## Working with code

The `dartlang` plugin shows errors and warnings in your code as you type. These
are displayed in a problems view at the bottom of Atom, in-line in the code, and
in a summary in the status line.

<img src="img/problems.png" width="75%" class="img-centered"/>

You can toggle the problems view on and off by clicking on the status line
summary, or by configuring it in the settings page.

<img src="img/status.png" width="20%" class="img-centered"/>

Clicking on an issue in the problems view will take you to that source code with
the problem. For some issues, the plugin can provide automated fixes - so called
'quick fixes'. When at a source location with errors, hit `ctrl-1`; if there are
any available fixes a menu with available options will be shown.

When looking at source code, you can get more information about a class, method,
or variable by placing the cursor on that symbol and hitting `F1`. The dartdoc
information for that element will be displayed.

Option-clicking on an element, or hitting `F3`, will jump to its definition.

You can toggle on and off a structural outline view of the current Dart file by
executing the command `'toggle outline view'`.

In order to find all the places where an element if referenced, right click on
that element and select the menu item `Find References`. You can also use the
key binding `shift-cmd-g`. The results will be displayed in a view on the right;
clicking on a result will jump to the associated source location. The results
view can be closed via the close button or by hitting the escape key twice.

To view the type hierarchy of a class, hit `F4` or right click on the class and
choose `Type Hierarchy`.

## Refactorings and code modifications

In addition to quick fixes, the plugin can also perform some automated code
transformations. These include a rename refactoring, available from the context
menu or via `option-shift-r`. Also, the plugin has the ability to automatically
organize import directives, available by the `'organize directives'` command or
`option-cmd-o`. Additionally, you can format a Dart source code using the
`'dart format'` command or the `option-cmd-b` key binding.

## Diagnosing analysis server issues

To view detailed info about what the analysis server is doing, run the
`'analysis server status'` command. This will let you know if the analysis
server is currently running, allow you to terminate and restart the server,
and let you re-analyze the Dart source for the current projects.

This status dialog can be useful for diagnosing issues with the analysis server,
like analysis not terminating, or excessive CPU or memory consumption.
