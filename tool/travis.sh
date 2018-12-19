#!/bin/bash

# Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# Fast fail the script on failures.
set -e

# Analyze, build and test.
# TODO: Re-enable the CI.
# Disable analysis and tests for now, until the codebase works under Dart 2.0.
#pub run grinder bot
