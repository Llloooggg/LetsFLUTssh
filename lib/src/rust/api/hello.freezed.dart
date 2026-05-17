// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hello.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbHelloProbeResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbHelloProbeResult()';
}


}

/// @nodoc
class $DbHelloProbeResultCopyWith<$Res>  {
$DbHelloProbeResultCopyWith(DbHelloProbeResult _, $Res Function(DbHelloProbeResult) __);
}


/// Adds pattern-matching-related methods to [DbHelloProbeResult].
extension DbHelloProbeResultPatterns on DbHelloProbeResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbHelloProbeResult_Available value)?  available,TResult Function( DbHelloProbeResult_ProviderUnavailable value)?  providerUnavailable,TResult Function( DbHelloProbeResult_HelloNotConfigured value)?  helloNotConfigured,TResult Function( DbHelloProbeResult_Unsupported value)?  unsupported,TResult Function( DbHelloProbeResult_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbHelloProbeResult_Available() when available != null:
return available(_that);case DbHelloProbeResult_ProviderUnavailable() when providerUnavailable != null:
return providerUnavailable(_that);case DbHelloProbeResult_HelloNotConfigured() when helloNotConfigured != null:
return helloNotConfigured(_that);case DbHelloProbeResult_Unsupported() when unsupported != null:
return unsupported(_that);case DbHelloProbeResult_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbHelloProbeResult_Available value)  available,required TResult Function( DbHelloProbeResult_ProviderUnavailable value)  providerUnavailable,required TResult Function( DbHelloProbeResult_HelloNotConfigured value)  helloNotConfigured,required TResult Function( DbHelloProbeResult_Unsupported value)  unsupported,required TResult Function( DbHelloProbeResult_Other value)  other,}){
final _that = this;
switch (_that) {
case DbHelloProbeResult_Available():
return available(_that);case DbHelloProbeResult_ProviderUnavailable():
return providerUnavailable(_that);case DbHelloProbeResult_HelloNotConfigured():
return helloNotConfigured(_that);case DbHelloProbeResult_Unsupported():
return unsupported(_that);case DbHelloProbeResult_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbHelloProbeResult_Available value)?  available,TResult? Function( DbHelloProbeResult_ProviderUnavailable value)?  providerUnavailable,TResult? Function( DbHelloProbeResult_HelloNotConfigured value)?  helloNotConfigured,TResult? Function( DbHelloProbeResult_Unsupported value)?  unsupported,TResult? Function( DbHelloProbeResult_Other value)?  other,}){
final _that = this;
switch (_that) {
case DbHelloProbeResult_Available() when available != null:
return available(_that);case DbHelloProbeResult_ProviderUnavailable() when providerUnavailable != null:
return providerUnavailable(_that);case DbHelloProbeResult_HelloNotConfigured() when helloNotConfigured != null:
return helloNotConfigured(_that);case DbHelloProbeResult_Unsupported() when unsupported != null:
return unsupported(_that);case DbHelloProbeResult_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DbHelloTpmTier tier)?  available,TResult Function( String field0)?  providerUnavailable,TResult Function()?  helloNotConfigured,TResult Function()?  unsupported,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbHelloProbeResult_Available() when available != null:
return available(_that.tier);case DbHelloProbeResult_ProviderUnavailable() when providerUnavailable != null:
return providerUnavailable(_that.field0);case DbHelloProbeResult_HelloNotConfigured() when helloNotConfigured != null:
return helloNotConfigured();case DbHelloProbeResult_Unsupported() when unsupported != null:
return unsupported();case DbHelloProbeResult_Other() when other != null:
return other(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DbHelloTpmTier tier)  available,required TResult Function( String field0)  providerUnavailable,required TResult Function()  helloNotConfigured,required TResult Function()  unsupported,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case DbHelloProbeResult_Available():
return available(_that.tier);case DbHelloProbeResult_ProviderUnavailable():
return providerUnavailable(_that.field0);case DbHelloProbeResult_HelloNotConfigured():
return helloNotConfigured();case DbHelloProbeResult_Unsupported():
return unsupported();case DbHelloProbeResult_Other():
return other(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DbHelloTpmTier tier)?  available,TResult? Function( String field0)?  providerUnavailable,TResult? Function()?  helloNotConfigured,TResult? Function()?  unsupported,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case DbHelloProbeResult_Available() when available != null:
return available(_that.tier);case DbHelloProbeResult_ProviderUnavailable() when providerUnavailable != null:
return providerUnavailable(_that.field0);case DbHelloProbeResult_HelloNotConfigured() when helloNotConfigured != null:
return helloNotConfigured();case DbHelloProbeResult_Unsupported() when unsupported != null:
return unsupported();case DbHelloProbeResult_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DbHelloProbeResult_Available extends DbHelloProbeResult {
  const DbHelloProbeResult_Available({required this.tier}): super._();
  

 final  DbHelloTpmTier tier;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbHelloProbeResult_AvailableCopyWith<DbHelloProbeResult_Available> get copyWith => _$DbHelloProbeResult_AvailableCopyWithImpl<DbHelloProbeResult_Available>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult_Available&&(identical(other.tier, tier) || other.tier == tier));
}


@override
int get hashCode => Object.hash(runtimeType,tier);

@override
String toString() {
  return 'DbHelloProbeResult.available(tier: $tier)';
}


}

/// @nodoc
abstract mixin class $DbHelloProbeResult_AvailableCopyWith<$Res> implements $DbHelloProbeResultCopyWith<$Res> {
  factory $DbHelloProbeResult_AvailableCopyWith(DbHelloProbeResult_Available value, $Res Function(DbHelloProbeResult_Available) _then) = _$DbHelloProbeResult_AvailableCopyWithImpl;
@useResult
$Res call({
 DbHelloTpmTier tier
});




}
/// @nodoc
class _$DbHelloProbeResult_AvailableCopyWithImpl<$Res>
    implements $DbHelloProbeResult_AvailableCopyWith<$Res> {
  _$DbHelloProbeResult_AvailableCopyWithImpl(this._self, this._then);

  final DbHelloProbeResult_Available _self;
  final $Res Function(DbHelloProbeResult_Available) _then;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? tier = null,}) {
  return _then(DbHelloProbeResult_Available(
tier: null == tier ? _self.tier : tier // ignore: cast_nullable_to_non_nullable
as DbHelloTpmTier,
  ));
}


}

/// @nodoc


class DbHelloProbeResult_ProviderUnavailable extends DbHelloProbeResult {
  const DbHelloProbeResult_ProviderUnavailable(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbHelloProbeResult_ProviderUnavailableCopyWith<DbHelloProbeResult_ProviderUnavailable> get copyWith => _$DbHelloProbeResult_ProviderUnavailableCopyWithImpl<DbHelloProbeResult_ProviderUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult_ProviderUnavailable&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbHelloProbeResult.providerUnavailable(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbHelloProbeResult_ProviderUnavailableCopyWith<$Res> implements $DbHelloProbeResultCopyWith<$Res> {
  factory $DbHelloProbeResult_ProviderUnavailableCopyWith(DbHelloProbeResult_ProviderUnavailable value, $Res Function(DbHelloProbeResult_ProviderUnavailable) _then) = _$DbHelloProbeResult_ProviderUnavailableCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbHelloProbeResult_ProviderUnavailableCopyWithImpl<$Res>
    implements $DbHelloProbeResult_ProviderUnavailableCopyWith<$Res> {
  _$DbHelloProbeResult_ProviderUnavailableCopyWithImpl(this._self, this._then);

  final DbHelloProbeResult_ProviderUnavailable _self;
  final $Res Function(DbHelloProbeResult_ProviderUnavailable) _then;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbHelloProbeResult_ProviderUnavailable(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbHelloProbeResult_HelloNotConfigured extends DbHelloProbeResult {
  const DbHelloProbeResult_HelloNotConfigured(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult_HelloNotConfigured);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbHelloProbeResult.helloNotConfigured()';
}


}




/// @nodoc


class DbHelloProbeResult_Unsupported extends DbHelloProbeResult {
  const DbHelloProbeResult_Unsupported(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbHelloProbeResult.unsupported()';
}


}




/// @nodoc


class DbHelloProbeResult_Other extends DbHelloProbeResult {
  const DbHelloProbeResult_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbHelloProbeResult_OtherCopyWith<DbHelloProbeResult_Other> get copyWith => _$DbHelloProbeResult_OtherCopyWithImpl<DbHelloProbeResult_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbHelloProbeResult_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbHelloProbeResult.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbHelloProbeResult_OtherCopyWith<$Res> implements $DbHelloProbeResultCopyWith<$Res> {
  factory $DbHelloProbeResult_OtherCopyWith(DbHelloProbeResult_Other value, $Res Function(DbHelloProbeResult_Other) _then) = _$DbHelloProbeResult_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbHelloProbeResult_OtherCopyWithImpl<$Res>
    implements $DbHelloProbeResult_OtherCopyWith<$Res> {
  _$DbHelloProbeResult_OtherCopyWithImpl(this._self, this._then);

  final DbHelloProbeResult_Other _self;
  final $Res Function(DbHelloProbeResult_Other) _then;

/// Create a copy of DbHelloProbeResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbHelloProbeResult_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
