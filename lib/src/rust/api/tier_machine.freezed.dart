// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tier_machine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbTierEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbTierEvent()';
}


}

/// @nodoc
class $DbTierEventCopyWith<$Res>  {
$DbTierEventCopyWith(DbTierEvent _, $Res Function(DbTierEvent) __);
}


/// Adds pattern-matching-related methods to [DbTierEvent].
extension DbTierEventPatterns on DbTierEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbTierEvent_UnlockRequested value)?  unlockRequested,TResult Function( DbTierEvent_UnlockSucceeded value)?  unlockSucceeded,TResult Function( DbTierEvent_UnlockFailed value)?  unlockFailed,TResult Function( DbTierEvent_LockRequested value)?  lockRequested,TResult Function( DbTierEvent_Wiped value)?  wiped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested() when unlockRequested != null:
return unlockRequested(_that);case DbTierEvent_UnlockSucceeded() when unlockSucceeded != null:
return unlockSucceeded(_that);case DbTierEvent_UnlockFailed() when unlockFailed != null:
return unlockFailed(_that);case DbTierEvent_LockRequested() when lockRequested != null:
return lockRequested(_that);case DbTierEvent_Wiped() when wiped != null:
return wiped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbTierEvent_UnlockRequested value)  unlockRequested,required TResult Function( DbTierEvent_UnlockSucceeded value)  unlockSucceeded,required TResult Function( DbTierEvent_UnlockFailed value)  unlockFailed,required TResult Function( DbTierEvent_LockRequested value)  lockRequested,required TResult Function( DbTierEvent_Wiped value)  wiped,}){
final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested():
return unlockRequested(_that);case DbTierEvent_UnlockSucceeded():
return unlockSucceeded(_that);case DbTierEvent_UnlockFailed():
return unlockFailed(_that);case DbTierEvent_LockRequested():
return lockRequested(_that);case DbTierEvent_Wiped():
return wiped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbTierEvent_UnlockRequested value)?  unlockRequested,TResult? Function( DbTierEvent_UnlockSucceeded value)?  unlockSucceeded,TResult? Function( DbTierEvent_UnlockFailed value)?  unlockFailed,TResult? Function( DbTierEvent_LockRequested value)?  lockRequested,TResult? Function( DbTierEvent_Wiped value)?  wiped,}){
final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested() when unlockRequested != null:
return unlockRequested(_that);case DbTierEvent_UnlockSucceeded() when unlockSucceeded != null:
return unlockSucceeded(_that);case DbTierEvent_UnlockFailed() when unlockFailed != null:
return unlockFailed(_that);case DbTierEvent_LockRequested() when lockRequested != null:
return lockRequested(_that);case DbTierEvent_Wiped() when wiped != null:
return wiped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unlockRequested,TResult Function()?  unlockSucceeded,TResult Function( DbUnlockFailureReason reason)?  unlockFailed,TResult Function()?  lockRequested,TResult Function()?  wiped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested() when unlockRequested != null:
return unlockRequested();case DbTierEvent_UnlockSucceeded() when unlockSucceeded != null:
return unlockSucceeded();case DbTierEvent_UnlockFailed() when unlockFailed != null:
return unlockFailed(_that.reason);case DbTierEvent_LockRequested() when lockRequested != null:
return lockRequested();case DbTierEvent_Wiped() when wiped != null:
return wiped();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unlockRequested,required TResult Function()  unlockSucceeded,required TResult Function( DbUnlockFailureReason reason)  unlockFailed,required TResult Function()  lockRequested,required TResult Function()  wiped,}) {final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested():
return unlockRequested();case DbTierEvent_UnlockSucceeded():
return unlockSucceeded();case DbTierEvent_UnlockFailed():
return unlockFailed(_that.reason);case DbTierEvent_LockRequested():
return lockRequested();case DbTierEvent_Wiped():
return wiped();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unlockRequested,TResult? Function()?  unlockSucceeded,TResult? Function( DbUnlockFailureReason reason)?  unlockFailed,TResult? Function()?  lockRequested,TResult? Function()?  wiped,}) {final _that = this;
switch (_that) {
case DbTierEvent_UnlockRequested() when unlockRequested != null:
return unlockRequested();case DbTierEvent_UnlockSucceeded() when unlockSucceeded != null:
return unlockSucceeded();case DbTierEvent_UnlockFailed() when unlockFailed != null:
return unlockFailed(_that.reason);case DbTierEvent_LockRequested() when lockRequested != null:
return lockRequested();case DbTierEvent_Wiped() when wiped != null:
return wiped();case _:
  return null;

}
}

}

/// @nodoc


class DbTierEvent_UnlockRequested extends DbTierEvent {
  const DbTierEvent_UnlockRequested(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent_UnlockRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbTierEvent.unlockRequested()';
}


}




/// @nodoc


class DbTierEvent_UnlockSucceeded extends DbTierEvent {
  const DbTierEvent_UnlockSucceeded(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent_UnlockSucceeded);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbTierEvent.unlockSucceeded()';
}


}




/// @nodoc


class DbTierEvent_UnlockFailed extends DbTierEvent {
  const DbTierEvent_UnlockFailed({required this.reason}): super._();
  

 final  DbUnlockFailureReason reason;

/// Create a copy of DbTierEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbTierEvent_UnlockFailedCopyWith<DbTierEvent_UnlockFailed> get copyWith => _$DbTierEvent_UnlockFailedCopyWithImpl<DbTierEvent_UnlockFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent_UnlockFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'DbTierEvent.unlockFailed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $DbTierEvent_UnlockFailedCopyWith<$Res> implements $DbTierEventCopyWith<$Res> {
  factory $DbTierEvent_UnlockFailedCopyWith(DbTierEvent_UnlockFailed value, $Res Function(DbTierEvent_UnlockFailed) _then) = _$DbTierEvent_UnlockFailedCopyWithImpl;
@useResult
$Res call({
 DbUnlockFailureReason reason
});


$DbUnlockFailureReasonCopyWith<$Res> get reason;

}
/// @nodoc
class _$DbTierEvent_UnlockFailedCopyWithImpl<$Res>
    implements $DbTierEvent_UnlockFailedCopyWith<$Res> {
  _$DbTierEvent_UnlockFailedCopyWithImpl(this._self, this._then);

  final DbTierEvent_UnlockFailed _self;
  final $Res Function(DbTierEvent_UnlockFailed) _then;

/// Create a copy of DbTierEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(DbTierEvent_UnlockFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as DbUnlockFailureReason,
  ));
}

/// Create a copy of DbTierEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DbUnlockFailureReasonCopyWith<$Res> get reason {
  
  return $DbUnlockFailureReasonCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class DbTierEvent_LockRequested extends DbTierEvent {
  const DbTierEvent_LockRequested(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent_LockRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbTierEvent.lockRequested()';
}


}




/// @nodoc


class DbTierEvent_Wiped extends DbTierEvent {
  const DbTierEvent_Wiped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbTierEvent_Wiped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbTierEvent.wiped()';
}


}




/// @nodoc
mixin _$DbUnlockFailureReason {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockFailureReason);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockFailureReason()';
}


}

/// @nodoc
class $DbUnlockFailureReasonCopyWith<$Res>  {
$DbUnlockFailureReasonCopyWith(DbUnlockFailureReason _, $Res Function(DbUnlockFailureReason) __);
}


/// Adds pattern-matching-related methods to [DbUnlockFailureReason].
extension DbUnlockFailureReasonPatterns on DbUnlockFailureReason {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbUnlockFailureReason_WrongSecret value)?  wrongSecret,TResult Function( DbUnlockFailureReason_PluginUnavailable value)?  pluginUnavailable,TResult Function( DbUnlockFailureReason_UserCancelled value)?  userCancelled,TResult Function( DbUnlockFailureReason_Corruption value)?  corruption,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret() when wrongSecret != null:
return wrongSecret(_that);case DbUnlockFailureReason_PluginUnavailable() when pluginUnavailable != null:
return pluginUnavailable(_that);case DbUnlockFailureReason_UserCancelled() when userCancelled != null:
return userCancelled(_that);case DbUnlockFailureReason_Corruption() when corruption != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbUnlockFailureReason_WrongSecret value)  wrongSecret,required TResult Function( DbUnlockFailureReason_PluginUnavailable value)  pluginUnavailable,required TResult Function( DbUnlockFailureReason_UserCancelled value)  userCancelled,required TResult Function( DbUnlockFailureReason_Corruption value)  corruption,}){
final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret():
return wrongSecret(_that);case DbUnlockFailureReason_PluginUnavailable():
return pluginUnavailable(_that);case DbUnlockFailureReason_UserCancelled():
return userCancelled(_that);case DbUnlockFailureReason_Corruption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbUnlockFailureReason_WrongSecret value)?  wrongSecret,TResult? Function( DbUnlockFailureReason_PluginUnavailable value)?  pluginUnavailable,TResult? Function( DbUnlockFailureReason_UserCancelled value)?  userCancelled,TResult? Function( DbUnlockFailureReason_Corruption value)?  corruption,}){
final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret() when wrongSecret != null:
return wrongSecret(_that);case DbUnlockFailureReason_PluginUnavailable() when pluginUnavailable != null:
return pluginUnavailable(_that);case DbUnlockFailureReason_UserCancelled() when userCancelled != null:
return userCancelled(_that);case DbUnlockFailureReason_Corruption() when corruption != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  wrongSecret,TResult Function( String code)?  pluginUnavailable,TResult Function()?  userCancelled,TResult Function( String detail)?  corruption,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret() when wrongSecret != null:
return wrongSecret();case DbUnlockFailureReason_PluginUnavailable() when pluginUnavailable != null:
return pluginUnavailable(_that.code);case DbUnlockFailureReason_UserCancelled() when userCancelled != null:
return userCancelled();case DbUnlockFailureReason_Corruption() when corruption != null:
return corruption(_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  wrongSecret,required TResult Function( String code)  pluginUnavailable,required TResult Function()  userCancelled,required TResult Function( String detail)  corruption,}) {final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret():
return wrongSecret();case DbUnlockFailureReason_PluginUnavailable():
return pluginUnavailable(_that.code);case DbUnlockFailureReason_UserCancelled():
return userCancelled();case DbUnlockFailureReason_Corruption():
return corruption(_that.detail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  wrongSecret,TResult? Function( String code)?  pluginUnavailable,TResult? Function()?  userCancelled,TResult? Function( String detail)?  corruption,}) {final _that = this;
switch (_that) {
case DbUnlockFailureReason_WrongSecret() when wrongSecret != null:
return wrongSecret();case DbUnlockFailureReason_PluginUnavailable() when pluginUnavailable != null:
return pluginUnavailable(_that.code);case DbUnlockFailureReason_UserCancelled() when userCancelled != null:
return userCancelled();case DbUnlockFailureReason_Corruption() when corruption != null:
return corruption(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class DbUnlockFailureReason_WrongSecret extends DbUnlockFailureReason {
  const DbUnlockFailureReason_WrongSecret(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockFailureReason_WrongSecret);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockFailureReason.wrongSecret()';
}


}




/// @nodoc


class DbUnlockFailureReason_PluginUnavailable extends DbUnlockFailureReason {
  const DbUnlockFailureReason_PluginUnavailable({required this.code}): super._();
  

 final  String code;

/// Create a copy of DbUnlockFailureReason
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbUnlockFailureReason_PluginUnavailableCopyWith<DbUnlockFailureReason_PluginUnavailable> get copyWith => _$DbUnlockFailureReason_PluginUnavailableCopyWithImpl<DbUnlockFailureReason_PluginUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockFailureReason_PluginUnavailable&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,code);

@override
String toString() {
  return 'DbUnlockFailureReason.pluginUnavailable(code: $code)';
}


}

/// @nodoc
abstract mixin class $DbUnlockFailureReason_PluginUnavailableCopyWith<$Res> implements $DbUnlockFailureReasonCopyWith<$Res> {
  factory $DbUnlockFailureReason_PluginUnavailableCopyWith(DbUnlockFailureReason_PluginUnavailable value, $Res Function(DbUnlockFailureReason_PluginUnavailable) _then) = _$DbUnlockFailureReason_PluginUnavailableCopyWithImpl;
@useResult
$Res call({
 String code
});




}
/// @nodoc
class _$DbUnlockFailureReason_PluginUnavailableCopyWithImpl<$Res>
    implements $DbUnlockFailureReason_PluginUnavailableCopyWith<$Res> {
  _$DbUnlockFailureReason_PluginUnavailableCopyWithImpl(this._self, this._then);

  final DbUnlockFailureReason_PluginUnavailable _self;
  final $Res Function(DbUnlockFailureReason_PluginUnavailable) _then;

/// Create a copy of DbUnlockFailureReason
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(DbUnlockFailureReason_PluginUnavailable(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbUnlockFailureReason_UserCancelled extends DbUnlockFailureReason {
  const DbUnlockFailureReason_UserCancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockFailureReason_UserCancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbUnlockFailureReason.userCancelled()';
}


}




/// @nodoc


class DbUnlockFailureReason_Corruption extends DbUnlockFailureReason {
  const DbUnlockFailureReason_Corruption({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of DbUnlockFailureReason
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbUnlockFailureReason_CorruptionCopyWith<DbUnlockFailureReason_Corruption> get copyWith => _$DbUnlockFailureReason_CorruptionCopyWithImpl<DbUnlockFailureReason_Corruption>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbUnlockFailureReason_Corruption&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'DbUnlockFailureReason.corruption(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $DbUnlockFailureReason_CorruptionCopyWith<$Res> implements $DbUnlockFailureReasonCopyWith<$Res> {
  factory $DbUnlockFailureReason_CorruptionCopyWith(DbUnlockFailureReason_Corruption value, $Res Function(DbUnlockFailureReason_Corruption) _then) = _$DbUnlockFailureReason_CorruptionCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$DbUnlockFailureReason_CorruptionCopyWithImpl<$Res>
    implements $DbUnlockFailureReason_CorruptionCopyWith<$Res> {
  _$DbUnlockFailureReason_CorruptionCopyWithImpl(this._self, this._then);

  final DbUnlockFailureReason_Corruption _self;
  final $Res Function(DbUnlockFailureReason_Corruption) _then;

/// Create a copy of DbUnlockFailureReason
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(DbUnlockFailureReason_Corruption(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
