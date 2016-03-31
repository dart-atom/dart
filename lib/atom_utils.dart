// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.atom_utils;

import 'dart:async';
import 'dart:html' show DivElement, Element, HttpRequest, Node, NodeValidator,
    NodeTreeSanitizer, window;

import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import 'atom.dart';
import 'state.dart';

final Logger _logger = new Logger('atom_utils');

/// Return a description of Atom, the plugin, and the OS.
Future<String> getSystemDescription({bool sdkPath: false}) {
  // 'Atom 1.0.11, dartlang 0.4.3, SDK 1.12 running on Windows.'
  String atomVer = atom.getVersion();
  String pluginVer;
  String sdkVer;
  String os = isMac ? 'macos' : process.platform;

  return atomPackage.getPackageVersion().then((ver) {
    pluginVer = ver;
    return sdkManager.hasSdk ? sdkManager.sdk.getVersion() : null;
  }).then((ver) {
    sdkVer = ver;

    String description = '\n\nAtom ${atomVer}, dartlang ${pluginVer}';
    if (sdkVer != null) description += ', SDK ${sdkVer}';
    description += ' running on ${os}.';

    if (sdkPath) {
      if (sdkManager.hasSdk) {
        description += '\nSDK at ${sdkManager.sdk.path}.';
      } else {
        description += '\nNo SDK configured.';
      }
    }

    return description;
  });
}

/// A [NodeValidator] which allows everything.
class PermissiveNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(Element element, String attributeName, String value) {
    return true;
  }
}
