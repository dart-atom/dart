// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.atom_utils;

import 'dart:async';
import 'dart:html' show Element, NodeValidator;

import 'package:atom/atom.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import 'state.dart';

final Logger _logger = new Logger('atom_utils');

/// Return a description of Atom, the plugin, and the OS.
Future<String> getSystemDescription({bool sdkPath: false}) async {
  // 'Atom 1.0.11, dartlang 0.4.3, SDK 1.12 running on Windows.'
  String atomVer = atom.getVersion();
  String os = isMac ? 'macos' : process.platform;
  String pluginVer = await atomPackage.getPackageVersion();
  String sdkVer = sdkManager.hasSdk ? await sdkManager.sdk.getVersion() : null;

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
}

/// A [NodeValidator] which allows everything.
class PermissiveNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(Element element, String attributeName, String value) {
    return true;
  }
}
