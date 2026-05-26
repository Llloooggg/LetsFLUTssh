// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recorder.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbRecordingLine {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbRecordingLine);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbRecordingLine()';
}


}

/// @nodoc
class $DbRecordingLineCopyWith<$Res>  {
$DbRecordingLineCopyWith(DbRecordingLine _, $Res Function(DbRecordingLine) __);
}


/// Adds pattern-matching-related methods to [DbRecordingLine].
extension DbRecordingLinePatterns on DbRecordingLine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbRecordingLine_Header value)?  header,TResult Function( DbRecordingLine_Event value)?  event,TResult Function( DbRecordingLine_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbRecordingLine_Header() when header != null:
return header(_that);case DbRecordingLine_Event() when event != null:
return event(_that);case DbRecordingLine_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbRecordingLine_Header value)  header,required TResult Function( DbRecordingLine_Event value)  event,required TResult Function( DbRecordingLine_Other value)  other,}){
final _that = this;
switch (_that) {
case DbRecordingLine_Header():
return header(_that);case DbRecordingLine_Event():
return event(_that);case DbRecordingLine_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbRecordingLine_Header value)?  header,TResult? Function( DbRecordingLine_Event value)?  event,TResult? Function( DbRecordingLine_Other value)?  other,}){
final _that = this;
switch (_that) {
case DbRecordingLine_Header() when header != null:
return header(_that);case DbRecordingLine_Event() when event != null:
return event(_that);case DbRecordingLine_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DbRecordingHeader field0)?  header,TResult Function( DbRecordingEvent field0)?  event,TResult Function()?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbRecordingLine_Header() when header != null:
return header(_that.field0);case DbRecordingLine_Event() when event != null:
return event(_that.field0);case DbRecordingLine_Other() when other != null:
return other();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DbRecordingHeader field0)  header,required TResult Function( DbRecordingEvent field0)  event,required TResult Function()  other,}) {final _that = this;
switch (_that) {
case DbRecordingLine_Header():
return header(_that.field0);case DbRecordingLine_Event():
return event(_that.field0);case DbRecordingLine_Other():
return other();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DbRecordingHeader field0)?  header,TResult? Function( DbRecordingEvent field0)?  event,TResult? Function()?  other,}) {final _that = this;
switch (_that) {
case DbRecordingLine_Header() when header != null:
return header(_that.field0);case DbRecordingLine_Event() when event != null:
return event(_that.field0);case DbRecordingLine_Other() when other != null:
return other();case _:
  return null;

}
}

}

/// @nodoc


class DbRecordingLine_Header extends DbRecordingLine {
  const DbRecordingLine_Header(this.field0): super._();
  

 final  DbRecordingHeader field0;

/// Create a copy of DbRecordingLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbRecordingLine_HeaderCopyWith<DbRecordingLine_Header> get copyWith => _$DbRecordingLine_HeaderCopyWithImpl<DbRecordingLine_Header>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbRecordingLine_Header&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbRecordingLine.header(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbRecordingLine_HeaderCopyWith<$Res> implements $DbRecordingLineCopyWith<$Res> {
  factory $DbRecordingLine_HeaderCopyWith(DbRecordingLine_Header value, $Res Function(DbRecordingLine_Header) _then) = _$DbRecordingLine_HeaderCopyWithImpl;
@useResult
$Res call({
 DbRecordingHeader field0
});




}
/// @nodoc
class _$DbRecordingLine_HeaderCopyWithImpl<$Res>
    implements $DbRecordingLine_HeaderCopyWith<$Res> {
  _$DbRecordingLine_HeaderCopyWithImpl(this._self, this._then);

  final DbRecordingLine_Header _self;
  final $Res Function(DbRecordingLine_Header) _then;

/// Create a copy of DbRecordingLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbRecordingLine_Header(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as DbRecordingHeader,
  ));
}


}

/// @nodoc


class DbRecordingLine_Event extends DbRecordingLine {
  const DbRecordingLine_Event(this.field0): super._();
  

 final  DbRecordingEvent field0;

/// Create a copy of DbRecordingLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbRecordingLine_EventCopyWith<DbRecordingLine_Event> get copyWith => _$DbRecordingLine_EventCopyWithImpl<DbRecordingLine_Event>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbRecordingLine_Event&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbRecordingLine.event(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbRecordingLine_EventCopyWith<$Res> implements $DbRecordingLineCopyWith<$Res> {
  factory $DbRecordingLine_EventCopyWith(DbRecordingLine_Event value, $Res Function(DbRecordingLine_Event) _then) = _$DbRecordingLine_EventCopyWithImpl;
@useResult
$Res call({
 DbRecordingEvent field0
});




}
/// @nodoc
class _$DbRecordingLine_EventCopyWithImpl<$Res>
    implements $DbRecordingLine_EventCopyWith<$Res> {
  _$DbRecordingLine_EventCopyWithImpl(this._self, this._then);

  final DbRecordingLine_Event _self;
  final $Res Function(DbRecordingLine_Event) _then;

/// Create a copy of DbRecordingLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbRecordingLine_Event(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as DbRecordingEvent,
  ));
}


}

/// @nodoc


class DbRecordingLine_Other extends DbRecordingLine {
  const DbRecordingLine_Other(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbRecordingLine_Other);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbRecordingLine.other()';
}


}




// dart format on
