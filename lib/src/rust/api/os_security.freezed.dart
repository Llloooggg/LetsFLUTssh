// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'os_security.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbBiometricAvailability {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability()';
}


}

/// @nodoc
class $DbBiometricAvailabilityCopyWith<$Res>  {
$DbBiometricAvailabilityCopyWith(DbBiometricAvailability _, $Res Function(DbBiometricAvailability) __);
}


/// Adds pattern-matching-related methods to [DbBiometricAvailability].
extension DbBiometricAvailabilityPatterns on DbBiometricAvailability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbBiometricAvailability_Available value)?  available,TResult Function( DbBiometricAvailability_PlatformUnsupported value)?  platformUnsupported,TResult Function( DbBiometricAvailability_NoSensor value)?  noSensor,TResult Function( DbBiometricAvailability_NotEnrolled value)?  notEnrolled,TResult Function( DbBiometricAvailability_SystemServiceMissing value)?  systemServiceMissing,TResult Function( DbBiometricAvailability_Probe value)?  probe,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbBiometricAvailability_Available() when available != null:
return available(_that);case DbBiometricAvailability_PlatformUnsupported() when platformUnsupported != null:
return platformUnsupported(_that);case DbBiometricAvailability_NoSensor() when noSensor != null:
return noSensor(_that);case DbBiometricAvailability_NotEnrolled() when notEnrolled != null:
return notEnrolled(_that);case DbBiometricAvailability_SystemServiceMissing() when systemServiceMissing != null:
return systemServiceMissing(_that);case DbBiometricAvailability_Probe() when probe != null:
return probe(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbBiometricAvailability_Available value)  available,required TResult Function( DbBiometricAvailability_PlatformUnsupported value)  platformUnsupported,required TResult Function( DbBiometricAvailability_NoSensor value)  noSensor,required TResult Function( DbBiometricAvailability_NotEnrolled value)  notEnrolled,required TResult Function( DbBiometricAvailability_SystemServiceMissing value)  systemServiceMissing,required TResult Function( DbBiometricAvailability_Probe value)  probe,}){
final _that = this;
switch (_that) {
case DbBiometricAvailability_Available():
return available(_that);case DbBiometricAvailability_PlatformUnsupported():
return platformUnsupported(_that);case DbBiometricAvailability_NoSensor():
return noSensor(_that);case DbBiometricAvailability_NotEnrolled():
return notEnrolled(_that);case DbBiometricAvailability_SystemServiceMissing():
return systemServiceMissing(_that);case DbBiometricAvailability_Probe():
return probe(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbBiometricAvailability_Available value)?  available,TResult? Function( DbBiometricAvailability_PlatformUnsupported value)?  platformUnsupported,TResult? Function( DbBiometricAvailability_NoSensor value)?  noSensor,TResult? Function( DbBiometricAvailability_NotEnrolled value)?  notEnrolled,TResult? Function( DbBiometricAvailability_SystemServiceMissing value)?  systemServiceMissing,TResult? Function( DbBiometricAvailability_Probe value)?  probe,}){
final _that = this;
switch (_that) {
case DbBiometricAvailability_Available() when available != null:
return available(_that);case DbBiometricAvailability_PlatformUnsupported() when platformUnsupported != null:
return platformUnsupported(_that);case DbBiometricAvailability_NoSensor() when noSensor != null:
return noSensor(_that);case DbBiometricAvailability_NotEnrolled() when notEnrolled != null:
return notEnrolled(_that);case DbBiometricAvailability_SystemServiceMissing() when systemServiceMissing != null:
return systemServiceMissing(_that);case DbBiometricAvailability_Probe() when probe != null:
return probe(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  available,TResult Function()?  platformUnsupported,TResult Function()?  noSensor,TResult Function()?  notEnrolled,TResult Function()?  systemServiceMissing,TResult Function( String field0)?  probe,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbBiometricAvailability_Available() when available != null:
return available();case DbBiometricAvailability_PlatformUnsupported() when platformUnsupported != null:
return platformUnsupported();case DbBiometricAvailability_NoSensor() when noSensor != null:
return noSensor();case DbBiometricAvailability_NotEnrolled() when notEnrolled != null:
return notEnrolled();case DbBiometricAvailability_SystemServiceMissing() when systemServiceMissing != null:
return systemServiceMissing();case DbBiometricAvailability_Probe() when probe != null:
return probe(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  available,required TResult Function()  platformUnsupported,required TResult Function()  noSensor,required TResult Function()  notEnrolled,required TResult Function()  systemServiceMissing,required TResult Function( String field0)  probe,}) {final _that = this;
switch (_that) {
case DbBiometricAvailability_Available():
return available();case DbBiometricAvailability_PlatformUnsupported():
return platformUnsupported();case DbBiometricAvailability_NoSensor():
return noSensor();case DbBiometricAvailability_NotEnrolled():
return notEnrolled();case DbBiometricAvailability_SystemServiceMissing():
return systemServiceMissing();case DbBiometricAvailability_Probe():
return probe(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  available,TResult? Function()?  platformUnsupported,TResult? Function()?  noSensor,TResult? Function()?  notEnrolled,TResult? Function()?  systemServiceMissing,TResult? Function( String field0)?  probe,}) {final _that = this;
switch (_that) {
case DbBiometricAvailability_Available() when available != null:
return available();case DbBiometricAvailability_PlatformUnsupported() when platformUnsupported != null:
return platformUnsupported();case DbBiometricAvailability_NoSensor() when noSensor != null:
return noSensor();case DbBiometricAvailability_NotEnrolled() when notEnrolled != null:
return notEnrolled();case DbBiometricAvailability_SystemServiceMissing() when systemServiceMissing != null:
return systemServiceMissing();case DbBiometricAvailability_Probe() when probe != null:
return probe(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DbBiometricAvailability_Available extends DbBiometricAvailability {
  const DbBiometricAvailability_Available(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_Available);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability.available()';
}


}




/// @nodoc


class DbBiometricAvailability_PlatformUnsupported extends DbBiometricAvailability {
  const DbBiometricAvailability_PlatformUnsupported(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_PlatformUnsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability.platformUnsupported()';
}


}




/// @nodoc


class DbBiometricAvailability_NoSensor extends DbBiometricAvailability {
  const DbBiometricAvailability_NoSensor(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_NoSensor);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability.noSensor()';
}


}




/// @nodoc


class DbBiometricAvailability_NotEnrolled extends DbBiometricAvailability {
  const DbBiometricAvailability_NotEnrolled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_NotEnrolled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability.notEnrolled()';
}


}




/// @nodoc


class DbBiometricAvailability_SystemServiceMissing extends DbBiometricAvailability {
  const DbBiometricAvailability_SystemServiceMissing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_SystemServiceMissing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbBiometricAvailability.systemServiceMissing()';
}


}




/// @nodoc


class DbBiometricAvailability_Probe extends DbBiometricAvailability {
  const DbBiometricAvailability_Probe(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbBiometricAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbBiometricAvailability_ProbeCopyWith<DbBiometricAvailability_Probe> get copyWith => _$DbBiometricAvailability_ProbeCopyWithImpl<DbBiometricAvailability_Probe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbBiometricAvailability_Probe&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbBiometricAvailability.probe(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbBiometricAvailability_ProbeCopyWith<$Res> implements $DbBiometricAvailabilityCopyWith<$Res> {
  factory $DbBiometricAvailability_ProbeCopyWith(DbBiometricAvailability_Probe value, $Res Function(DbBiometricAvailability_Probe) _then) = _$DbBiometricAvailability_ProbeCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbBiometricAvailability_ProbeCopyWithImpl<$Res>
    implements $DbBiometricAvailability_ProbeCopyWith<$Res> {
  _$DbBiometricAvailability_ProbeCopyWithImpl(this._self, this._then);

  final DbBiometricAvailability_Probe _self;
  final $Res Function(DbBiometricAvailability_Probe) _then;

/// Create a copy of DbBiometricAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbBiometricAvailability_Probe(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
