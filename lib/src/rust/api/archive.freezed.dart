// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'archive.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbImportOpenError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbImportOpenError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbImportOpenError()';
}


}

/// @nodoc
class $DbImportOpenErrorCopyWith<$Res>  {
$DbImportOpenErrorCopyWith(DbImportOpenError _, $Res Function(DbImportOpenError) __);
}


/// Adds pattern-matching-related methods to [DbImportOpenError].
extension DbImportOpenErrorPatterns on DbImportOpenError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbImportOpenError_FutureVersion value)?  futureVersion,TResult Function( DbImportOpenError_Generic value)?  generic,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion() when futureVersion != null:
return futureVersion(_that);case DbImportOpenError_Generic() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbImportOpenError_FutureVersion value)  futureVersion,required TResult Function( DbImportOpenError_Generic value)  generic,}){
final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion():
return futureVersion(_that);case DbImportOpenError_Generic():
return generic(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbImportOpenError_FutureVersion value)?  futureVersion,TResult? Function( DbImportOpenError_Generic value)?  generic,}){
final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion() when futureVersion != null:
return futureVersion(_that);case DbImportOpenError_Generic() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 found,  int supported)?  futureVersion,TResult Function( String field0)?  generic,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion() when futureVersion != null:
return futureVersion(_that.found,_that.supported);case DbImportOpenError_Generic() when generic != null:
return generic(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 found,  int supported)  futureVersion,required TResult Function( String field0)  generic,}) {final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion():
return futureVersion(_that.found,_that.supported);case DbImportOpenError_Generic():
return generic(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 found,  int supported)?  futureVersion,TResult? Function( String field0)?  generic,}) {final _that = this;
switch (_that) {
case DbImportOpenError_FutureVersion() when futureVersion != null:
return futureVersion(_that.found,_that.supported);case DbImportOpenError_Generic() when generic != null:
return generic(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DbImportOpenError_FutureVersion extends DbImportOpenError {
  const DbImportOpenError_FutureVersion({required this.found, required this.supported}): super._();
  

 final  PlatformInt64 found;
 final  int supported;

/// Create a copy of DbImportOpenError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbImportOpenError_FutureVersionCopyWith<DbImportOpenError_FutureVersion> get copyWith => _$DbImportOpenError_FutureVersionCopyWithImpl<DbImportOpenError_FutureVersion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbImportOpenError_FutureVersion&&(identical(other.found, found) || other.found == found)&&(identical(other.supported, supported) || other.supported == supported));
}


@override
int get hashCode => Object.hash(runtimeType,found,supported);

@override
String toString() {
  return 'DbImportOpenError.futureVersion(found: $found, supported: $supported)';
}


}

/// @nodoc
abstract mixin class $DbImportOpenError_FutureVersionCopyWith<$Res> implements $DbImportOpenErrorCopyWith<$Res> {
  factory $DbImportOpenError_FutureVersionCopyWith(DbImportOpenError_FutureVersion value, $Res Function(DbImportOpenError_FutureVersion) _then) = _$DbImportOpenError_FutureVersionCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 found, int supported
});




}
/// @nodoc
class _$DbImportOpenError_FutureVersionCopyWithImpl<$Res>
    implements $DbImportOpenError_FutureVersionCopyWith<$Res> {
  _$DbImportOpenError_FutureVersionCopyWithImpl(this._self, this._then);

  final DbImportOpenError_FutureVersion _self;
  final $Res Function(DbImportOpenError_FutureVersion) _then;

/// Create a copy of DbImportOpenError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? found = null,Object? supported = null,}) {
  return _then(DbImportOpenError_FutureVersion(
found: null == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as PlatformInt64,supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DbImportOpenError_Generic extends DbImportOpenError {
  const DbImportOpenError_Generic(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbImportOpenError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbImportOpenError_GenericCopyWith<DbImportOpenError_Generic> get copyWith => _$DbImportOpenError_GenericCopyWithImpl<DbImportOpenError_Generic>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbImportOpenError_Generic&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbImportOpenError.generic(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbImportOpenError_GenericCopyWith<$Res> implements $DbImportOpenErrorCopyWith<$Res> {
  factory $DbImportOpenError_GenericCopyWith(DbImportOpenError_Generic value, $Res Function(DbImportOpenError_Generic) _then) = _$DbImportOpenError_GenericCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbImportOpenError_GenericCopyWithImpl<$Res>
    implements $DbImportOpenError_GenericCopyWith<$Res> {
  _$DbImportOpenError_GenericCopyWithImpl(this._self, this._then);

  final DbImportOpenError_Generic _self;
  final $Res Function(DbImportOpenError_Generic) _then;

/// Create a copy of DbImportOpenError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbImportOpenError_Generic(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
