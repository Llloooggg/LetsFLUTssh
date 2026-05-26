// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tier_unlock_orchestrator.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbUnlockOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockOutcome()';
}


}

/// @nodoc
class $DbUnlockOutcomeCopyWith<$Res>  {
$DbUnlockOutcomeCopyWith(DbUnlockOutcome _, $Res Function(DbUnlockOutcome) __);
}


/// Adds pattern-matching-related methods to [DbUnlockOutcome].
extension DbUnlockOutcomePatterns on DbUnlockOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbUnlockOutcome_Staged value)?  staged,TResult Function( DbUnlockOutcome_WrongSecret value)?  wrongSecret,TResult Function( DbUnlockOutcome_Cancelled value)?  cancelled,TResult Function( DbUnlockOutcome_PluginError value)?  pluginError,TResult Function( DbUnlockOutcome_Corruption value)?  corruption,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged() when staged != null:
return staged(_that);case DbUnlockOutcome_WrongSecret() when wrongSecret != null:
return wrongSecret(_that);case DbUnlockOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case DbUnlockOutcome_PluginError() when pluginError != null:
return pluginError(_that);case DbUnlockOutcome_Corruption() when corruption != null:
return corruption(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbUnlockOutcome_Staged value)  staged,required TResult Function( DbUnlockOutcome_WrongSecret value)  wrongSecret,required TResult Function( DbUnlockOutcome_Cancelled value)  cancelled,required TResult Function( DbUnlockOutcome_PluginError value)  pluginError,required TResult Function( DbUnlockOutcome_Corruption value)  corruption,}){
final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged():
return staged(_that);case DbUnlockOutcome_WrongSecret():
return wrongSecret(_that);case DbUnlockOutcome_Cancelled():
return cancelled(_that);case DbUnlockOutcome_PluginError():
return pluginError(_that);case DbUnlockOutcome_Corruption():
return corruption(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbUnlockOutcome_Staged value)?  staged,TResult? Function( DbUnlockOutcome_WrongSecret value)?  wrongSecret,TResult? Function( DbUnlockOutcome_Cancelled value)?  cancelled,TResult? Function( DbUnlockOutcome_PluginError value)?  pluginError,TResult? Function( DbUnlockOutcome_Corruption value)?  corruption,}){
final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged() when staged != null:
return staged(_that);case DbUnlockOutcome_WrongSecret() when wrongSecret != null:
return wrongSecret(_that);case DbUnlockOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case DbUnlockOutcome_PluginError() when pluginError != null:
return pluginError(_that);case DbUnlockOutcome_Corruption() when corruption != null:
return corruption(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  staged,TResult Function()?  wrongSecret,TResult Function()?  cancelled,TResult Function( String field0)?  pluginError,TResult Function( String field0)?  corruption,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged() when staged != null:
return staged();case DbUnlockOutcome_WrongSecret() when wrongSecret != null:
return wrongSecret();case DbUnlockOutcome_Cancelled() when cancelled != null:
return cancelled();case DbUnlockOutcome_PluginError() when pluginError != null:
return pluginError(_that.field0);case DbUnlockOutcome_Corruption() when corruption != null:
return corruption(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  staged,required TResult Function()  wrongSecret,required TResult Function()  cancelled,required TResult Function( String field0)  pluginError,required TResult Function( String field0)  corruption,}) {final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged():
return staged();case DbUnlockOutcome_WrongSecret():
return wrongSecret();case DbUnlockOutcome_Cancelled():
return cancelled();case DbUnlockOutcome_PluginError():
return pluginError(_that.field0);case DbUnlockOutcome_Corruption():
return corruption(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  staged,TResult? Function()?  wrongSecret,TResult? Function()?  cancelled,TResult? Function( String field0)?  pluginError,TResult? Function( String field0)?  corruption,}) {final _that = this;
switch (_that) {
case DbUnlockOutcome_Staged() when staged != null:
return staged();case DbUnlockOutcome_WrongSecret() when wrongSecret != null:
return wrongSecret();case DbUnlockOutcome_Cancelled() when cancelled != null:
return cancelled();case DbUnlockOutcome_PluginError() when pluginError != null:
return pluginError(_that.field0);case DbUnlockOutcome_Corruption() when corruption != null:
return corruption(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DbUnlockOutcome_Staged extends DbUnlockOutcome {
  const DbUnlockOutcome_Staged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome_Staged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockOutcome.staged()';
}


}




/// @nodoc


class DbUnlockOutcome_WrongSecret extends DbUnlockOutcome {
  const DbUnlockOutcome_WrongSecret(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome_WrongSecret);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockOutcome.wrongSecret()';
}


}




/// @nodoc


class DbUnlockOutcome_Cancelled extends DbUnlockOutcome {
  const DbUnlockOutcome_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockOutcome.cancelled()';
}


}




/// @nodoc


class DbUnlockOutcome_PluginError extends DbUnlockOutcome {
  const DbUnlockOutcome_PluginError(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbUnlockOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbUnlockOutcome_PluginErrorCopyWith<DbUnlockOutcome_PluginError> get copyWith => _$DbUnlockOutcome_PluginErrorCopyWithImpl<DbUnlockOutcome_PluginError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome_PluginError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbUnlockOutcome.pluginError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbUnlockOutcome_PluginErrorCopyWith<$Res> implements $DbUnlockOutcomeCopyWith<$Res> {
  factory $DbUnlockOutcome_PluginErrorCopyWith(DbUnlockOutcome_PluginError value, $Res Function(DbUnlockOutcome_PluginError) _then) = _$DbUnlockOutcome_PluginErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbUnlockOutcome_PluginErrorCopyWithImpl<$Res>
    implements $DbUnlockOutcome_PluginErrorCopyWith<$Res> {
  _$DbUnlockOutcome_PluginErrorCopyWithImpl(this._self, this._then);

  final DbUnlockOutcome_PluginError _self;
  final $Res Function(DbUnlockOutcome_PluginError) _then;

/// Create a copy of DbUnlockOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbUnlockOutcome_PluginError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbUnlockOutcome_Corruption extends DbUnlockOutcome {
  const DbUnlockOutcome_Corruption(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbUnlockOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbUnlockOutcome_CorruptionCopyWith<DbUnlockOutcome_Corruption> get copyWith => _$DbUnlockOutcome_CorruptionCopyWithImpl<DbUnlockOutcome_Corruption>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockOutcome_Corruption&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbUnlockOutcome.corruption(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbUnlockOutcome_CorruptionCopyWith<$Res> implements $DbUnlockOutcomeCopyWith<$Res> {
  factory $DbUnlockOutcome_CorruptionCopyWith(DbUnlockOutcome_Corruption value, $Res Function(DbUnlockOutcome_Corruption) _then) = _$DbUnlockOutcome_CorruptionCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbUnlockOutcome_CorruptionCopyWithImpl<$Res>
    implements $DbUnlockOutcome_CorruptionCopyWith<$Res> {
  _$DbUnlockOutcome_CorruptionCopyWithImpl(this._self, this._then);

  final DbUnlockOutcome_Corruption _self;
  final $Res Function(DbUnlockOutcome_Corruption) _then;

/// Create a copy of DbUnlockOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbUnlockOutcome_Corruption(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
