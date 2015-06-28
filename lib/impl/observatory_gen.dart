// This is a generated file.

library observatory_gen;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

final Logger _logger = new Logger('observatory_gen');

const optional = 'optional';

class Observatory {

  /// The [addBreakpoint] RPC is used to add a breakpoint at a specific line of
  /// some script.
  Future addBreakpoint() {}

  /// The [addBreakpointAtEntry] RPC is used to add a breakpoint at the
  /// entrypoint of some function.
  Future addBreakpointAtEntry() {}

  /// The [evaluate] RPC is used to evaluate an expression in the context of
  /// some target.
  Future evaluate() {}

  /// The [evaluateInFrame] RPC is used to evaluate an expression in the context
  /// of a particular stack frame. [frameIndex] is the index of the desired
  /// Frame, with an index of [0] indicating the top (most recent) frame.
  Future evaluateInFrame() {}

  /// The _getFlagList RPC returns a list of all command line flags in the VM
  /// along with their current values.
  Future getFlagList() {}

  /// The [getIsolate] RPC is used to lookup an [Isolate] object by its [id].
  Future getIsolate() {}

  /// The [getObject] RPC is used to lookup an [object] from some isolate by its
  /// [id].
  Future getObject() {}

  /// The [getStack] RPC is used to retrieve the current execution stack and
  /// message queue for an isolate. The isolate does not need to be paused.
  Future getStack() {}

  /// The [getVersion] RPC is used to determine what version of the Service
  /// Protocol is served by a VM.
  Future getVersion() {}

  /// The [getVM] RPC returns global information about a Dart virtual machine.
  Future getVM() {}

  /// The [pause] RPC is used to interrupt a running isolate. The RPC enqueues
  /// the interrupt request and potentially returns before the isolate is
  /// paused.
  Future pause() {}

  /// The [removeBreakpoint] RPC is used to remove a breakpoint by its [id].
  Future removeBreakpoint() {}

  /// The [resume] RPC is used to resume execution of a paused isolate.
  Future resume() {}

  /// The [setName] RPC is used to change the debugging name for an isolate.
  Future setName() {}

  /// The [setLibraryDebuggable] RPC is used to enable or disable whether
  /// breakpoints and stepping work for a given library.
  Future setLibraryDebuggable() {}

  /// The [streamCancel] RPC cancels a stream subscription in the VM.
  Future streamCancel() {}

  /// The [streamListen] RPC subscribes to a stream in the VM. Once subscribed,
  /// the client will begin receiving events from the stream.
  Future streamListen() {}
}

// enums

/// Adding new values to [EventKind] is considered a backwards compatible
/// change. Clients should ignore unrecognized events.
enum EventKind { foo }

/// Adding new values to [InstanceKind] is considered a backwards compatible
/// change. Clients should treat unrecognized instance kinds as [PlainInstance].
enum InstanceKind { foo }

/// A [SentinelKind] is used to distinguish different kinds of [Sentinel]
/// objects.
enum SentinelKind { foo }

/// A [StepOption] indicates which form of stepping is requested in a resume
/// RPC.
enum StepOption { foo }

// types

/// A [BoundField] represents a field bound to a particular value in an
/// [Instance].
class BoundField {}

/// A [BoundVariable] represents a local variable bound to a particular value in
/// a [Frame].
class BoundVariable {}

/// A [Breakpoint] describes a debugger breakpoint.
class Breakpoint {}

/// [ClassRef] is a reference to a [Class].
class ClassRef {}

/// A [Class] provides information about a Dart language class.
class Class {}

/// [CodeRef] is a reference to a [Code] object.
class CodeRef {}

/// A [Code] object represents compiled code in the Dart VM.
class Code {}

/// [ErrorRef] is a reference to an [Error].
class ErrorRef {}

/// An [Error] represents a Dart language level error. This is distinct from an
/// rpc error.
class Error {}

/// An [Event] is an asynchronous notification from the VM. It is delivered only
/// when the client has subscribed to an event stream using the streamListen
/// RPC.
class Event {}

/// An [FieldRef] is a reference to a [Field].
class FieldRef {}

/// A [Field] provides information about a Dart language field or variable.
class Field {}

/// A [Flag] represents a single VM command line flag.
class Flag {}

/// A [FlagList] represents the complete set of VM command line flags.
class FlagList {}

/// An [FunctionRef] is a reference to a [Function].
class FunctionRef {}

/// A [Function] represents a Dart language function.
class Function {}

/// [InstanceRef] is a reference to an [Instance].
class InstanceRef {}

/// An [Instance] represents an instance of the Dart language class [Object].
class Instance {}

/// [IsolateRef] is a reference to an [Isolate] object.
class IsolateRef {}

/// An [Isolate] object provides information about one isolate in the VM.
class Isolate {}

/// [LibraryRef] is a reference to a [Library].
class LibraryRef {}

/// A [Library] provides information about a Dart language library.
class Library {}

/// A [LibraryDependency] provides information about an import or export.
class LibraryDependency {}

/// [NullRef] is a reference to an a [Null].
class NullRef {}

/// A [Null] object represents the Dart language value null.
class Null {}

/// [ObjectRef] is a reference to a [Object].
class ObjectRef {}

/// An [Object] is a persistent object that is owned by some isolate.
class Object {}

/// A [Sentinel] is used to indicate that the normal response is not available.
class Sentinel {}

/// [ScriptRef] is a reference to a [Script].
class ScriptRef {}

/// A [Script] provides information about a Dart language script.
class Script {}

/// The [SourceLocation] class is used to designate a position or range in some
/// script.
class SourceLocation {}

/// The [Success] type is used to indicate that an operation completed
/// successfully.
class Success {}

/// [TypeArgumentsRef] is a reference to a [TypeArguments] object.
class TypeArgumentsRef {}

/// A [TypeArguments] object represents the type argument vector for some
/// instantiated generic type.
class TypeArguments {}

/// Every non-error response returned by the Service Protocol extends
/// [Response]. By using the [type] property, the client can determine which
/// type of response has been provided.
class Response {}

/// See Versioning.
class Version {}
