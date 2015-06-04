# Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

{CompositeDisposable} = require 'atom'

module.exports = DartLang =
  subscriptions: null

  activate: (state) ->
    console.log('dart-lang activate')
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace', 'dart-lang:hello-world': =>
      @helloWorld()

  deactivate: ->
    console.log('dart-lang deactivate')
    @subscriptions.dispose()

  serialize: ->

  helloWorld: ->
    atom.notifications.addInfo('Hello world from dart-lang')
