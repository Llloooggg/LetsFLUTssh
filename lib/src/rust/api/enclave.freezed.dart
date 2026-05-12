// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'enclave.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbEnclaveAvailability {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability()';
}


}

/// @nodoc
class $DbEnclaveAvailabilityCopyWith<$Res>  {
$DbEnclaveAvailabilityCopyWith(DbEnclaveAvailability _, $Res Function(DbEnclaveAvailability) __);
}


/// Adds pattern-matching-related methods to [DbEnclaveAvailability].
extension DbEnclaveAvailabilityPatterns on DbEnclaveAvailability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbEnclaveAvailability_Available value)?  available,TResult Function( DbEnclaveAvailability_CodeSignRequired value)?  codeSignRequired,TResult Function( DbEnclaveAvailability_NoSecureEnclave value)?  noSecureEnclave,TResult Function( DbEnclaveAvailability_PasscodeNotSet value)?  passcodeNotSet,TResult Function( DbEnclaveAvailability_Other value)?  other,TResult Function( DbEnclaveAvailability_UnsupportedPlatform value)?  unsupportedPlatform,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available() when available != null:
return available(_that);case DbEnclaveAvailability_CodeSignRequired() when codeSignRequired != null:
return codeSignRequired(_that);case DbEnclaveAvailability_NoSecureEnclave() when noSecureEnclave != null:
return noSecureEnclave(_that);case DbEnclaveAvailability_PasscodeNotSet() when passcodeNotSet != null:
return passcodeNotSet(_that);case DbEnclaveAvailability_Other() when other != null:
return other(_that);case DbEnclaveAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbEnclaveAvailability_Available value)  available,required TResult Function( DbEnclaveAvailability_CodeSignRequired value)  codeSignRequired,required TResult Function( DbEnclaveAvailability_NoSecureEnclave value)  noSecureEnclave,required TResult Function( DbEnclaveAvailability_PasscodeNotSet value)  passcodeNotSet,required TResult Function( DbEnclaveAvailability_Other value)  other,required TResult Function( DbEnclaveAvailability_UnsupportedPlatform value)  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available():
return available(_that);case DbEnclaveAvailability_CodeSignRequired():
return codeSignRequired(_that);case DbEnclaveAvailability_NoSecureEnclave():
return noSecureEnclave(_that);case DbEnclaveAvailability_PasscodeNotSet():
return passcodeNotSet(_that);case DbEnclaveAvailability_Other():
return other(_that);case DbEnclaveAvailability_UnsupportedPlatform():
return unsupportedPlatform(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbEnclaveAvailability_Available value)?  available,TResult? Function( DbEnclaveAvailability_CodeSignRequired value)?  codeSignRequired,TResult? Function( DbEnclaveAvailability_NoSecureEnclave value)?  noSecureEnclave,TResult? Function( DbEnclaveAvailability_PasscodeNotSet value)?  passcodeNotSet,TResult? Function( DbEnclaveAvailability_Other value)?  other,TResult? Function( DbEnclaveAvailability_UnsupportedPlatform value)?  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available() when available != null:
return available(_that);case DbEnclaveAvailability_CodeSignRequired() when codeSignRequired != null:
return codeSignRequired(_that);case DbEnclaveAvailability_NoSecureEnclave() when noSecureEnclave != null:
return noSecureEnclave(_that);case DbEnclaveAvailability_PasscodeNotSet() when passcodeNotSet != null:
return passcodeNotSet(_that);case DbEnclaveAvailability_Other() when other != null:
return other(_that);case DbEnclaveAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  available,TResult Function()?  codeSignRequired,TResult Function()?  noSecureEnclave,TResult Function()?  passcodeNotSet,TResult Function( String field0)?  other,TResult Function()?  unsupportedPlatform,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available() when available != null:
return available();case DbEnclaveAvailability_CodeSignRequired() when codeSignRequired != null:
return codeSignRequired();case DbEnclaveAvailability_NoSecureEnclave() when noSecureEnclave != null:
return noSecureEnclave();case DbEnclaveAvailability_PasscodeNotSet() when passcodeNotSet != null:
return passcodeNotSet();case DbEnclaveAvailability_Other() when other != null:
return other(_that.field0);case DbEnclaveAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  available,required TResult Function()  codeSignRequired,required TResult Function()  noSecureEnclave,required TResult Function()  passcodeNotSet,required TResult Function( String field0)  other,required TResult Function()  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available():
return available();case DbEnclaveAvailability_CodeSignRequired():
return codeSignRequired();case DbEnclaveAvailability_NoSecureEnclave():
return noSecureEnclave();case DbEnclaveAvailability_PasscodeNotSet():
return passcodeNotSet();case DbEnclaveAvailability_Other():
return other(_that.field0);case DbEnclaveAvailability_UnsupportedPlatform():
return unsupportedPlatform();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  available,TResult? Function()?  codeSignRequired,TResult? Function()?  noSecureEnclave,TResult? Function()?  passcodeNotSet,TResult? Function( String field0)?  other,TResult? Function()?  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case DbEnclaveAvailability_Available() when available != null:
return available();case DbEnclaveAvailability_CodeSignRequired() when codeSignRequired != null:
return codeSignRequired();case DbEnclaveAvailability_NoSecureEnclave() when noSecureEnclave != null:
return noSecureEnclave();case DbEnclaveAvailability_PasscodeNotSet() when passcodeNotSet != null:
return passcodeNotSet();case DbEnclaveAvailability_Other() when other != null:
return other(_that.field0);case DbEnclaveAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
  return null;

}
}

}

/// @nodoc


class DbEnclaveAvailability_Available extends DbEnclaveAvailability {
  const DbEnclaveAvailability_Available(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_Available);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability.available()';
}


}




/// @nodoc


class DbEnclaveAvailability_CodeSignRequired extends DbEnclaveAvailability {
  const DbEnclaveAvailability_CodeSignRequired(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_CodeSignRequired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability.codeSignRequired()';
}


}




/// @nodoc


class DbEnclaveAvailability_NoSecureEnclave extends DbEnclaveAvailability {
  const DbEnclaveAvailability_NoSecureEnclave(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_NoSecureEnclave);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability.noSecureEnclave()';
}


}




/// @nodoc


class DbEnclaveAvailability_PasscodeNotSet extends DbEnclaveAvailability {
  const DbEnclaveAvailability_PasscodeNotSet(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_PasscodeNotSet);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability.passcodeNotSet()';
}


}




/// @nodoc


class DbEnclaveAvailability_Other extends DbEnclaveAvailability {
  const DbEnclaveAvailability_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbEnclaveAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbEnclaveAvailability_OtherCopyWith<DbEnclaveAvailability_Other> get copyWith => _$DbEnclaveAvailability_OtherCopyWithImpl<DbEnclaveAvailability_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbEnclaveAvailability.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbEnclaveAvailability_OtherCopyWith<$Res> implements $DbEnclaveAvailabilityCopyWith<$Res> {
  factory $DbEnclaveAvailability_OtherCopyWith(DbEnclaveAvailability_Other value, $Res Function(DbEnclaveAvailability_Other) _then) = _$DbEnclaveAvailability_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbEnclaveAvailability_OtherCopyWithImpl<$Res>
    implements $DbEnclaveAvailability_OtherCopyWith<$Res> {
  _$DbEnclaveAvailability_OtherCopyWithImpl(this._self, this._then);

  final DbEnclaveAvailability_Other _self;
  final $Res Function(DbEnclaveAvailability_Other) _then;

/// Create a copy of DbEnclaveAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbEnclaveAvailability_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbEnclaveAvailability_UnsupportedPlatform extends DbEnclaveAvailability {
  const DbEnclaveAvailability_UnsupportedPlatform(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbEnclaveAvailability_UnsupportedPlatform);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbEnclaveAvailability.unsupportedPlatform()';
}


}




// dart format on
