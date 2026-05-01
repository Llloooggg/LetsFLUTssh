// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'secure_key_storage.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbSecureStorageOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSecureStorageOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbSecureStorageOutcome()';
}


}

/// @nodoc
class $DbSecureStorageOutcomeCopyWith<$Res>  {
$DbSecureStorageOutcomeCopyWith(DbSecureStorageOutcome _, $Res Function(DbSecureStorageOutcome) __);
}


/// Adds pattern-matching-related methods to [DbSecureStorageOutcome].
extension DbSecureStorageOutcomePatterns on DbSecureStorageOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbSecureStorageOutcome_Found value)?  found,TResult Function( DbSecureStorageOutcome_NotFound value)?  notFound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found() when found != null:
return found(_that);case DbSecureStorageOutcome_NotFound() when notFound != null:
return notFound(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbSecureStorageOutcome_Found value)  found,required TResult Function( DbSecureStorageOutcome_NotFound value)  notFound,}){
final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found():
return found(_that);case DbSecureStorageOutcome_NotFound():
return notFound(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbSecureStorageOutcome_Found value)?  found,TResult? Function( DbSecureStorageOutcome_NotFound value)?  notFound,}){
final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found() when found != null:
return found(_that);case DbSecureStorageOutcome_NotFound() when notFound != null:
return notFound(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List field0)?  found,TResult Function()?  notFound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found() when found != null:
return found(_that.field0);case DbSecureStorageOutcome_NotFound() when notFound != null:
return notFound();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List field0)  found,required TResult Function()  notFound,}) {final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found():
return found(_that.field0);case DbSecureStorageOutcome_NotFound():
return notFound();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List field0)?  found,TResult? Function()?  notFound,}) {final _that = this;
switch (_that) {
case DbSecureStorageOutcome_Found() when found != null:
return found(_that.field0);case DbSecureStorageOutcome_NotFound() when notFound != null:
return notFound();case _:
  return null;

}
}

}

/// @nodoc


class DbSecureStorageOutcome_Found extends DbSecureStorageOutcome {
  const DbSecureStorageOutcome_Found(this.field0): super._();
  

 final  Uint8List field0;

/// Create a copy of DbSecureStorageOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSecureStorageOutcome_FoundCopyWith<DbSecureStorageOutcome_Found> get copyWith => _$DbSecureStorageOutcome_FoundCopyWithImpl<DbSecureStorageOutcome_Found>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSecureStorageOutcome_Found&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'DbSecureStorageOutcome.found(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSecureStorageOutcome_FoundCopyWith<$Res> implements $DbSecureStorageOutcomeCopyWith<$Res> {
  factory $DbSecureStorageOutcome_FoundCopyWith(DbSecureStorageOutcome_Found value, $Res Function(DbSecureStorageOutcome_Found) _then) = _$DbSecureStorageOutcome_FoundCopyWithImpl;
@useResult
$Res call({
 Uint8List field0
});




}
/// @nodoc
class _$DbSecureStorageOutcome_FoundCopyWithImpl<$Res>
    implements $DbSecureStorageOutcome_FoundCopyWith<$Res> {
  _$DbSecureStorageOutcome_FoundCopyWithImpl(this._self, this._then);

  final DbSecureStorageOutcome_Found _self;
  final $Res Function(DbSecureStorageOutcome_Found) _then;

/// Create a copy of DbSecureStorageOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSecureStorageOutcome_Found(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class DbSecureStorageOutcome_NotFound extends DbSecureStorageOutcome {
  const DbSecureStorageOutcome_NotFound(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSecureStorageOutcome_NotFound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbSecureStorageOutcome.notFound()';
}


}




// dart format on
