// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshShellEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SshShellEvent()';
}


}

/// @nodoc
class $SshShellEventCopyWith<$Res>  {
$SshShellEventCopyWith(SshShellEvent _, $Res Function(SshShellEvent) __);
}


/// Adds pattern-matching-related methods to [SshShellEvent].
extension SshShellEventPatterns on SshShellEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SshShellEvent_Output value)?  output,TResult Function( SshShellEvent_ExtendedOutput value)?  extendedOutput,TResult Function( SshShellEvent_Eof value)?  eof,TResult Function( SshShellEvent_ExitStatus value)?  exitStatus,TResult Function( SshShellEvent_ExitSignal value)?  exitSignal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SshShellEvent_Output() when output != null:
return output(_that);case SshShellEvent_ExtendedOutput() when extendedOutput != null:
return extendedOutput(_that);case SshShellEvent_Eof() when eof != null:
return eof(_that);case SshShellEvent_ExitStatus() when exitStatus != null:
return exitStatus(_that);case SshShellEvent_ExitSignal() when exitSignal != null:
return exitSignal(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SshShellEvent_Output value)  output,required TResult Function( SshShellEvent_ExtendedOutput value)  extendedOutput,required TResult Function( SshShellEvent_Eof value)  eof,required TResult Function( SshShellEvent_ExitStatus value)  exitStatus,required TResult Function( SshShellEvent_ExitSignal value)  exitSignal,}){
final _that = this;
switch (_that) {
case SshShellEvent_Output():
return output(_that);case SshShellEvent_ExtendedOutput():
return extendedOutput(_that);case SshShellEvent_Eof():
return eof(_that);case SshShellEvent_ExitStatus():
return exitStatus(_that);case SshShellEvent_ExitSignal():
return exitSignal(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SshShellEvent_Output value)?  output,TResult? Function( SshShellEvent_ExtendedOutput value)?  extendedOutput,TResult? Function( SshShellEvent_Eof value)?  eof,TResult? Function( SshShellEvent_ExitStatus value)?  exitStatus,TResult? Function( SshShellEvent_ExitSignal value)?  exitSignal,}){
final _that = this;
switch (_that) {
case SshShellEvent_Output() when output != null:
return output(_that);case SshShellEvent_ExtendedOutput() when extendedOutput != null:
return extendedOutput(_that);case SshShellEvent_Eof() when eof != null:
return eof(_that);case SshShellEvent_ExitStatus() when exitStatus != null:
return exitStatus(_that);case SshShellEvent_ExitSignal() when exitSignal != null:
return exitSignal(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List field0)?  output,TResult Function( Uint8List field0)?  extendedOutput,TResult Function()?  eof,TResult Function( int field0)?  exitStatus,TResult Function( String field0)?  exitSignal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SshShellEvent_Output() when output != null:
return output(_that.field0);case SshShellEvent_ExtendedOutput() when extendedOutput != null:
return extendedOutput(_that.field0);case SshShellEvent_Eof() when eof != null:
return eof();case SshShellEvent_ExitStatus() when exitStatus != null:
return exitStatus(_that.field0);case SshShellEvent_ExitSignal() when exitSignal != null:
return exitSignal(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List field0)  output,required TResult Function( Uint8List field0)  extendedOutput,required TResult Function()  eof,required TResult Function( int field0)  exitStatus,required TResult Function( String field0)  exitSignal,}) {final _that = this;
switch (_that) {
case SshShellEvent_Output():
return output(_that.field0);case SshShellEvent_ExtendedOutput():
return extendedOutput(_that.field0);case SshShellEvent_Eof():
return eof();case SshShellEvent_ExitStatus():
return exitStatus(_that.field0);case SshShellEvent_ExitSignal():
return exitSignal(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List field0)?  output,TResult? Function( Uint8List field0)?  extendedOutput,TResult? Function()?  eof,TResult? Function( int field0)?  exitStatus,TResult? Function( String field0)?  exitSignal,}) {final _that = this;
switch (_that) {
case SshShellEvent_Output() when output != null:
return output(_that.field0);case SshShellEvent_ExtendedOutput() when extendedOutput != null:
return extendedOutput(_that.field0);case SshShellEvent_Eof() when eof != null:
return eof();case SshShellEvent_ExitStatus() when exitStatus != null:
return exitStatus(_that.field0);case SshShellEvent_ExitSignal() when exitSignal != null:
return exitSignal(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class SshShellEvent_Output extends SshShellEvent {
  const SshShellEvent_Output(this.field0): super._();
  

 final  Uint8List field0;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshShellEvent_OutputCopyWith<SshShellEvent_Output> get copyWith => _$SshShellEvent_OutputCopyWithImpl<SshShellEvent_Output>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent_Output&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'SshShellEvent.output(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $SshShellEvent_OutputCopyWith<$Res> implements $SshShellEventCopyWith<$Res> {
  factory $SshShellEvent_OutputCopyWith(SshShellEvent_Output value, $Res Function(SshShellEvent_Output) _then) = _$SshShellEvent_OutputCopyWithImpl;
@useResult
$Res call({
 Uint8List field0
});




}
/// @nodoc
class _$SshShellEvent_OutputCopyWithImpl<$Res>
    implements $SshShellEvent_OutputCopyWith<$Res> {
  _$SshShellEvent_OutputCopyWithImpl(this._self, this._then);

  final SshShellEvent_Output _self;
  final $Res Function(SshShellEvent_Output) _then;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(SshShellEvent_Output(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class SshShellEvent_ExtendedOutput extends SshShellEvent {
  const SshShellEvent_ExtendedOutput(this.field0): super._();
  

 final  Uint8List field0;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshShellEvent_ExtendedOutputCopyWith<SshShellEvent_ExtendedOutput> get copyWith => _$SshShellEvent_ExtendedOutputCopyWithImpl<SshShellEvent_ExtendedOutput>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent_ExtendedOutput&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'SshShellEvent.extendedOutput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $SshShellEvent_ExtendedOutputCopyWith<$Res> implements $SshShellEventCopyWith<$Res> {
  factory $SshShellEvent_ExtendedOutputCopyWith(SshShellEvent_ExtendedOutput value, $Res Function(SshShellEvent_ExtendedOutput) _then) = _$SshShellEvent_ExtendedOutputCopyWithImpl;
@useResult
$Res call({
 Uint8List field0
});




}
/// @nodoc
class _$SshShellEvent_ExtendedOutputCopyWithImpl<$Res>
    implements $SshShellEvent_ExtendedOutputCopyWith<$Res> {
  _$SshShellEvent_ExtendedOutputCopyWithImpl(this._self, this._then);

  final SshShellEvent_ExtendedOutput _self;
  final $Res Function(SshShellEvent_ExtendedOutput) _then;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(SshShellEvent_ExtendedOutput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class SshShellEvent_Eof extends SshShellEvent {
  const SshShellEvent_Eof(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent_Eof);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SshShellEvent.eof()';
}


}




/// @nodoc


class SshShellEvent_ExitStatus extends SshShellEvent {
  const SshShellEvent_ExitStatus(this.field0): super._();
  

 final  int field0;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshShellEvent_ExitStatusCopyWith<SshShellEvent_ExitStatus> get copyWith => _$SshShellEvent_ExitStatusCopyWithImpl<SshShellEvent_ExitStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent_ExitStatus&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'SshShellEvent.exitStatus(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $SshShellEvent_ExitStatusCopyWith<$Res> implements $SshShellEventCopyWith<$Res> {
  factory $SshShellEvent_ExitStatusCopyWith(SshShellEvent_ExitStatus value, $Res Function(SshShellEvent_ExitStatus) _then) = _$SshShellEvent_ExitStatusCopyWithImpl;
@useResult
$Res call({
 int field0
});




}
/// @nodoc
class _$SshShellEvent_ExitStatusCopyWithImpl<$Res>
    implements $SshShellEvent_ExitStatusCopyWith<$Res> {
  _$SshShellEvent_ExitStatusCopyWithImpl(this._self, this._then);

  final SshShellEvent_ExitStatus _self;
  final $Res Function(SshShellEvent_ExitStatus) _then;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(SshShellEvent_ExitStatus(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class SshShellEvent_ExitSignal extends SshShellEvent {
  const SshShellEvent_ExitSignal(this.field0): super._();
  

 final  String field0;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshShellEvent_ExitSignalCopyWith<SshShellEvent_ExitSignal> get copyWith => _$SshShellEvent_ExitSignalCopyWithImpl<SshShellEvent_ExitSignal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshShellEvent_ExitSignal&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'SshShellEvent.exitSignal(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $SshShellEvent_ExitSignalCopyWith<$Res> implements $SshShellEventCopyWith<$Res> {
  factory $SshShellEvent_ExitSignalCopyWith(SshShellEvent_ExitSignal value, $Res Function(SshShellEvent_ExitSignal) _then) = _$SshShellEvent_ExitSignalCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$SshShellEvent_ExitSignalCopyWithImpl<$Res>
    implements $SshShellEvent_ExitSignalCopyWith<$Res> {
  _$SshShellEvent_ExitSignalCopyWithImpl(this._self, this._then);

  final SshShellEvent_ExitSignal _self;
  final $Res Function(SshShellEvent_ExitSignal) _then;

/// Create a copy of SshShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(SshShellEvent_ExitSignal(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
