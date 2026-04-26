// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bus.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BusCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusCommand()';
}


}

/// @nodoc
class $BusCommandCopyWith<$Res>  {
$BusCommandCopyWith(BusCommand _, $Res Function(BusCommand) __);
}


/// Adds pattern-matching-related methods to [BusCommand].
extension BusCommandPatterns on BusCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusCommand_NoopEcho value)?  noopEcho,TResult Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,TResult Function( BusCommand_ConnectionDisconnectAll value)?  connectionDisconnectAll,TResult Function( BusCommand_AutoLockOnPointerActivity value)?  autoLockOnPointerActivity,TResult Function( BusCommand_AutoLockOnLifecycleChange value)?  autoLockOnLifecycleChange,TResult Function( BusCommand_AutoLockSetTimeout value)?  autoLockSetTimeout,TResult Function( BusCommand_AutoLockRequestLock value)?  autoLockRequestLock,TResult Function( BusCommand_AutoLockUnlock value)?  autoLockUnlock,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll(_that);case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity(_that);case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock(_that);case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusCommand_NoopEcho value)  noopEcho,required TResult Function( BusCommand_ConnectionDisconnect value)  connectionDisconnect,required TResult Function( BusCommand_ConnectionDisconnectAll value)  connectionDisconnectAll,required TResult Function( BusCommand_AutoLockOnPointerActivity value)  autoLockOnPointerActivity,required TResult Function( BusCommand_AutoLockOnLifecycleChange value)  autoLockOnLifecycleChange,required TResult Function( BusCommand_AutoLockSetTimeout value)  autoLockSetTimeout,required TResult Function( BusCommand_AutoLockRequestLock value)  autoLockRequestLock,required TResult Function( BusCommand_AutoLockUnlock value)  autoLockUnlock,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that);case BusCommand_ConnectionDisconnect():
return connectionDisconnect(_that);case BusCommand_ConnectionDisconnectAll():
return connectionDisconnectAll(_that);case BusCommand_AutoLockOnPointerActivity():
return autoLockOnPointerActivity(_that);case BusCommand_AutoLockOnLifecycleChange():
return autoLockOnLifecycleChange(_that);case BusCommand_AutoLockSetTimeout():
return autoLockSetTimeout(_that);case BusCommand_AutoLockRequestLock():
return autoLockRequestLock(_that);case BusCommand_AutoLockUnlock():
return autoLockUnlock(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusCommand_NoopEcho value)?  noopEcho,TResult? Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,TResult? Function( BusCommand_ConnectionDisconnectAll value)?  connectionDisconnectAll,TResult? Function( BusCommand_AutoLockOnPointerActivity value)?  autoLockOnPointerActivity,TResult? Function( BusCommand_AutoLockOnLifecycleChange value)?  autoLockOnLifecycleChange,TResult? Function( BusCommand_AutoLockSetTimeout value)?  autoLockSetTimeout,TResult? Function( BusCommand_AutoLockRequestLock value)?  autoLockRequestLock,TResult? Function( BusCommand_AutoLockUnlock value)?  autoLockUnlock,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll(_that);case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity(_that);case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock(_that);case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  noopEcho,TResult Function( String id)?  connectionDisconnect,TResult Function()?  connectionDisconnectAll,TResult Function()?  autoLockOnPointerActivity,TResult Function( bool background)?  autoLockOnLifecycleChange,TResult Function( PlatformInt64 minutes)?  autoLockSetTimeout,TResult Function()?  autoLockRequestLock,TResult Function()?  autoLockUnlock,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock();case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  noopEcho,required TResult Function( String id)  connectionDisconnect,required TResult Function()  connectionDisconnectAll,required TResult Function()  autoLockOnPointerActivity,required TResult Function( bool background)  autoLockOnLifecycleChange,required TResult Function( PlatformInt64 minutes)  autoLockSetTimeout,required TResult Function()  autoLockRequestLock,required TResult Function()  autoLockUnlock,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect():
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll():
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity():
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange():
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout():
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock():
return autoLockRequestLock();case BusCommand_AutoLockUnlock():
return autoLockUnlock();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  noopEcho,TResult? Function( String id)?  connectionDisconnect,TResult? Function()?  connectionDisconnectAll,TResult? Function()?  autoLockOnPointerActivity,TResult? Function( bool background)?  autoLockOnLifecycleChange,TResult? Function( PlatformInt64 minutes)?  autoLockSetTimeout,TResult? Function()?  autoLockRequestLock,TResult? Function()?  autoLockUnlock,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock();case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock();case _:
  return null;

}
}

}

/// @nodoc


class BusCommand_NoopEcho extends BusCommand {
  const BusCommand_NoopEcho({required this.payload}): super._();
  

 final  String payload;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommand_NoopEchoCopyWith<BusCommand_NoopEcho> get copyWith => _$BusCommand_NoopEchoCopyWithImpl<BusCommand_NoopEcho>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_NoopEcho&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,payload);

@override
String toString() {
  return 'BusCommand.noopEcho(payload: $payload)';
}


}

/// @nodoc
abstract mixin class $BusCommand_NoopEchoCopyWith<$Res> implements $BusCommandCopyWith<$Res> {
  factory $BusCommand_NoopEchoCopyWith(BusCommand_NoopEcho value, $Res Function(BusCommand_NoopEcho) _then) = _$BusCommand_NoopEchoCopyWithImpl;
@useResult
$Res call({
 String payload
});




}
/// @nodoc
class _$BusCommand_NoopEchoCopyWithImpl<$Res>
    implements $BusCommand_NoopEchoCopyWith<$Res> {
  _$BusCommand_NoopEchoCopyWithImpl(this._self, this._then);

  final BusCommand_NoopEcho _self;
  final $Res Function(BusCommand_NoopEcho) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? payload = null,}) {
  return _then(BusCommand_NoopEcho(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusCommand_ConnectionDisconnect extends BusCommand {
  const BusCommand_ConnectionDisconnect({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommand_ConnectionDisconnectCopyWith<BusCommand_ConnectionDisconnect> get copyWith => _$BusCommand_ConnectionDisconnectCopyWithImpl<BusCommand_ConnectionDisconnect>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_ConnectionDisconnect&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusCommand.connectionDisconnect(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusCommand_ConnectionDisconnectCopyWith<$Res> implements $BusCommandCopyWith<$Res> {
  factory $BusCommand_ConnectionDisconnectCopyWith(BusCommand_ConnectionDisconnect value, $Res Function(BusCommand_ConnectionDisconnect) _then) = _$BusCommand_ConnectionDisconnectCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusCommand_ConnectionDisconnectCopyWithImpl<$Res>
    implements $BusCommand_ConnectionDisconnectCopyWith<$Res> {
  _$BusCommand_ConnectionDisconnectCopyWithImpl(this._self, this._then);

  final BusCommand_ConnectionDisconnect _self;
  final $Res Function(BusCommand_ConnectionDisconnect) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusCommand_ConnectionDisconnect(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusCommand_ConnectionDisconnectAll extends BusCommand {
  const BusCommand_ConnectionDisconnectAll(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_ConnectionDisconnectAll);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusCommand.connectionDisconnectAll()';
}


}




/// @nodoc


class BusCommand_AutoLockOnPointerActivity extends BusCommand {
  const BusCommand_AutoLockOnPointerActivity(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_AutoLockOnPointerActivity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusCommand.autoLockOnPointerActivity()';
}


}




/// @nodoc


class BusCommand_AutoLockOnLifecycleChange extends BusCommand {
  const BusCommand_AutoLockOnLifecycleChange({required this.background}): super._();
  

 final  bool background;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommand_AutoLockOnLifecycleChangeCopyWith<BusCommand_AutoLockOnLifecycleChange> get copyWith => _$BusCommand_AutoLockOnLifecycleChangeCopyWithImpl<BusCommand_AutoLockOnLifecycleChange>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_AutoLockOnLifecycleChange&&(identical(other.background, background) || other.background == background));
}


@override
int get hashCode => Object.hash(runtimeType,background);

@override
String toString() {
  return 'BusCommand.autoLockOnLifecycleChange(background: $background)';
}


}

/// @nodoc
abstract mixin class $BusCommand_AutoLockOnLifecycleChangeCopyWith<$Res> implements $BusCommandCopyWith<$Res> {
  factory $BusCommand_AutoLockOnLifecycleChangeCopyWith(BusCommand_AutoLockOnLifecycleChange value, $Res Function(BusCommand_AutoLockOnLifecycleChange) _then) = _$BusCommand_AutoLockOnLifecycleChangeCopyWithImpl;
@useResult
$Res call({
 bool background
});




}
/// @nodoc
class _$BusCommand_AutoLockOnLifecycleChangeCopyWithImpl<$Res>
    implements $BusCommand_AutoLockOnLifecycleChangeCopyWith<$Res> {
  _$BusCommand_AutoLockOnLifecycleChangeCopyWithImpl(this._self, this._then);

  final BusCommand_AutoLockOnLifecycleChange _self;
  final $Res Function(BusCommand_AutoLockOnLifecycleChange) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? background = null,}) {
  return _then(BusCommand_AutoLockOnLifecycleChange(
background: null == background ? _self.background : background // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BusCommand_AutoLockSetTimeout extends BusCommand {
  const BusCommand_AutoLockSetTimeout({required this.minutes}): super._();
  

 final  PlatformInt64 minutes;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommand_AutoLockSetTimeoutCopyWith<BusCommand_AutoLockSetTimeout> get copyWith => _$BusCommand_AutoLockSetTimeoutCopyWithImpl<BusCommand_AutoLockSetTimeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_AutoLockSetTimeout&&(identical(other.minutes, minutes) || other.minutes == minutes));
}


@override
int get hashCode => Object.hash(runtimeType,minutes);

@override
String toString() {
  return 'BusCommand.autoLockSetTimeout(minutes: $minutes)';
}


}

/// @nodoc
abstract mixin class $BusCommand_AutoLockSetTimeoutCopyWith<$Res> implements $BusCommandCopyWith<$Res> {
  factory $BusCommand_AutoLockSetTimeoutCopyWith(BusCommand_AutoLockSetTimeout value, $Res Function(BusCommand_AutoLockSetTimeout) _then) = _$BusCommand_AutoLockSetTimeoutCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 minutes
});




}
/// @nodoc
class _$BusCommand_AutoLockSetTimeoutCopyWithImpl<$Res>
    implements $BusCommand_AutoLockSetTimeoutCopyWith<$Res> {
  _$BusCommand_AutoLockSetTimeoutCopyWithImpl(this._self, this._then);

  final BusCommand_AutoLockSetTimeout _self;
  final $Res Function(BusCommand_AutoLockSetTimeout) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? minutes = null,}) {
  return _then(BusCommand_AutoLockSetTimeout(
minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BusCommand_AutoLockRequestLock extends BusCommand {
  const BusCommand_AutoLockRequestLock(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_AutoLockRequestLock);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusCommand.autoLockRequestLock()';
}


}




/// @nodoc


class BusCommand_AutoLockUnlock extends BusCommand {
  const BusCommand_AutoLockUnlock(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_AutoLockUnlock);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusCommand.autoLockUnlock()';
}


}




/// @nodoc
mixin _$BusConnectAuthRef {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusConnectAuthRef);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusConnectAuthRef()';
}


}

/// @nodoc
class $BusConnectAuthRefCopyWith<$Res>  {
$BusConnectAuthRefCopyWith(BusConnectAuthRef _, $Res Function(BusConnectAuthRef) __);
}


/// Adds pattern-matching-related methods to [BusConnectAuthRef].
extension BusConnectAuthRefPatterns on BusConnectAuthRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusConnectAuthRef_Password value)?  password,TResult Function( BusConnectAuthRef_Pubkey value)?  pubkey,TResult Function( BusConnectAuthRef_PubkeyCert value)?  pubkeyCert,TResult Function( BusConnectAuthRef_Agent value)?  agent,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusConnectAuthRef_Password() when password != null:
return password(_that);case BusConnectAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case BusConnectAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case BusConnectAuthRef_Agent() when agent != null:
return agent(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusConnectAuthRef_Password value)  password,required TResult Function( BusConnectAuthRef_Pubkey value)  pubkey,required TResult Function( BusConnectAuthRef_PubkeyCert value)  pubkeyCert,required TResult Function( BusConnectAuthRef_Agent value)  agent,}){
final _that = this;
switch (_that) {
case BusConnectAuthRef_Password():
return password(_that);case BusConnectAuthRef_Pubkey():
return pubkey(_that);case BusConnectAuthRef_PubkeyCert():
return pubkeyCert(_that);case BusConnectAuthRef_Agent():
return agent(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusConnectAuthRef_Password value)?  password,TResult? Function( BusConnectAuthRef_Pubkey value)?  pubkey,TResult? Function( BusConnectAuthRef_PubkeyCert value)?  pubkeyCert,TResult? Function( BusConnectAuthRef_Agent value)?  agent,}){
final _that = this;
switch (_that) {
case BusConnectAuthRef_Password() when password != null:
return password(_that);case BusConnectAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case BusConnectAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case BusConnectAuthRef_Agent() when agent != null:
return agent(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String secretId)?  password,TResult Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,TResult Function()?  agent,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusConnectAuthRef_Password() when password != null:
return password(_that.secretId);case BusConnectAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case BusConnectAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case BusConnectAuthRef_Agent() when agent != null:
return agent();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String secretId)  password,required TResult Function( String keySecretId,  String? passphraseSecretId)  pubkey,required TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)  pubkeyCert,required TResult Function()  agent,}) {final _that = this;
switch (_that) {
case BusConnectAuthRef_Password():
return password(_that.secretId);case BusConnectAuthRef_Pubkey():
return pubkey(_that.keySecretId,_that.passphraseSecretId);case BusConnectAuthRef_PubkeyCert():
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case BusConnectAuthRef_Agent():
return agent();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String secretId)?  password,TResult? Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult? Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,TResult? Function()?  agent,}) {final _that = this;
switch (_that) {
case BusConnectAuthRef_Password() when password != null:
return password(_that.secretId);case BusConnectAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case BusConnectAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case BusConnectAuthRef_Agent() when agent != null:
return agent();case _:
  return null;

}
}

}

/// @nodoc


class BusConnectAuthRef_Password extends BusConnectAuthRef {
  const BusConnectAuthRef_Password({required this.secretId}): super._();
  

 final  String secretId;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusConnectAuthRef_PasswordCopyWith<BusConnectAuthRef_Password> get copyWith => _$BusConnectAuthRef_PasswordCopyWithImpl<BusConnectAuthRef_Password>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusConnectAuthRef_Password&&(identical(other.secretId, secretId) || other.secretId == secretId));
}


@override
int get hashCode => Object.hash(runtimeType,secretId);

@override
String toString() {
  return 'BusConnectAuthRef.password(secretId: $secretId)';
}


}

/// @nodoc
abstract mixin class $BusConnectAuthRef_PasswordCopyWith<$Res> implements $BusConnectAuthRefCopyWith<$Res> {
  factory $BusConnectAuthRef_PasswordCopyWith(BusConnectAuthRef_Password value, $Res Function(BusConnectAuthRef_Password) _then) = _$BusConnectAuthRef_PasswordCopyWithImpl;
@useResult
$Res call({
 String secretId
});




}
/// @nodoc
class _$BusConnectAuthRef_PasswordCopyWithImpl<$Res>
    implements $BusConnectAuthRef_PasswordCopyWith<$Res> {
  _$BusConnectAuthRef_PasswordCopyWithImpl(this._self, this._then);

  final BusConnectAuthRef_Password _self;
  final $Res Function(BusConnectAuthRef_Password) _then;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? secretId = null,}) {
  return _then(BusConnectAuthRef_Password(
secretId: null == secretId ? _self.secretId : secretId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusConnectAuthRef_Pubkey extends BusConnectAuthRef {
  const BusConnectAuthRef_Pubkey({required this.keySecretId, this.passphraseSecretId}): super._();
  

 final  String keySecretId;
 final  String? passphraseSecretId;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusConnectAuthRef_PubkeyCopyWith<BusConnectAuthRef_Pubkey> get copyWith => _$BusConnectAuthRef_PubkeyCopyWithImpl<BusConnectAuthRef_Pubkey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusConnectAuthRef_Pubkey&&(identical(other.keySecretId, keySecretId) || other.keySecretId == keySecretId)&&(identical(other.passphraseSecretId, passphraseSecretId) || other.passphraseSecretId == passphraseSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,keySecretId,passphraseSecretId);

@override
String toString() {
  return 'BusConnectAuthRef.pubkey(keySecretId: $keySecretId, passphraseSecretId: $passphraseSecretId)';
}


}

/// @nodoc
abstract mixin class $BusConnectAuthRef_PubkeyCopyWith<$Res> implements $BusConnectAuthRefCopyWith<$Res> {
  factory $BusConnectAuthRef_PubkeyCopyWith(BusConnectAuthRef_Pubkey value, $Res Function(BusConnectAuthRef_Pubkey) _then) = _$BusConnectAuthRef_PubkeyCopyWithImpl;
@useResult
$Res call({
 String keySecretId, String? passphraseSecretId
});




}
/// @nodoc
class _$BusConnectAuthRef_PubkeyCopyWithImpl<$Res>
    implements $BusConnectAuthRef_PubkeyCopyWith<$Res> {
  _$BusConnectAuthRef_PubkeyCopyWithImpl(this._self, this._then);

  final BusConnectAuthRef_Pubkey _self;
  final $Res Function(BusConnectAuthRef_Pubkey) _then;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keySecretId = null,Object? passphraseSecretId = freezed,}) {
  return _then(BusConnectAuthRef_Pubkey(
keySecretId: null == keySecretId ? _self.keySecretId : keySecretId // ignore: cast_nullable_to_non_nullable
as String,passphraseSecretId: freezed == passphraseSecretId ? _self.passphraseSecretId : passphraseSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BusConnectAuthRef_PubkeyCert extends BusConnectAuthRef {
  const BusConnectAuthRef_PubkeyCert({required this.keySecretId, required this.certSecretId, this.passphraseSecretId}): super._();
  

 final  String keySecretId;
 final  String certSecretId;
 final  String? passphraseSecretId;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusConnectAuthRef_PubkeyCertCopyWith<BusConnectAuthRef_PubkeyCert> get copyWith => _$BusConnectAuthRef_PubkeyCertCopyWithImpl<BusConnectAuthRef_PubkeyCert>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusConnectAuthRef_PubkeyCert&&(identical(other.keySecretId, keySecretId) || other.keySecretId == keySecretId)&&(identical(other.certSecretId, certSecretId) || other.certSecretId == certSecretId)&&(identical(other.passphraseSecretId, passphraseSecretId) || other.passphraseSecretId == passphraseSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,keySecretId,certSecretId,passphraseSecretId);

@override
String toString() {
  return 'BusConnectAuthRef.pubkeyCert(keySecretId: $keySecretId, certSecretId: $certSecretId, passphraseSecretId: $passphraseSecretId)';
}


}

/// @nodoc
abstract mixin class $BusConnectAuthRef_PubkeyCertCopyWith<$Res> implements $BusConnectAuthRefCopyWith<$Res> {
  factory $BusConnectAuthRef_PubkeyCertCopyWith(BusConnectAuthRef_PubkeyCert value, $Res Function(BusConnectAuthRef_PubkeyCert) _then) = _$BusConnectAuthRef_PubkeyCertCopyWithImpl;
@useResult
$Res call({
 String keySecretId, String certSecretId, String? passphraseSecretId
});




}
/// @nodoc
class _$BusConnectAuthRef_PubkeyCertCopyWithImpl<$Res>
    implements $BusConnectAuthRef_PubkeyCertCopyWith<$Res> {
  _$BusConnectAuthRef_PubkeyCertCopyWithImpl(this._self, this._then);

  final BusConnectAuthRef_PubkeyCert _self;
  final $Res Function(BusConnectAuthRef_PubkeyCert) _then;

/// Create a copy of BusConnectAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keySecretId = null,Object? certSecretId = null,Object? passphraseSecretId = freezed,}) {
  return _then(BusConnectAuthRef_PubkeyCert(
keySecretId: null == keySecretId ? _self.keySecretId : keySecretId // ignore: cast_nullable_to_non_nullable
as String,certSecretId: null == certSecretId ? _self.certSecretId : certSecretId // ignore: cast_nullable_to_non_nullable
as String,passphraseSecretId: freezed == passphraseSecretId ? _self.passphraseSecretId : passphraseSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BusConnectAuthRef_Agent extends BusConnectAuthRef {
  const BusConnectAuthRef_Agent(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusConnectAuthRef_Agent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusConnectAuthRef.agent()';
}


}




/// @nodoc
mixin _$BusEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusEvent()';
}


}

/// @nodoc
class $BusEventCopyWith<$Res>  {
$BusEventCopyWith(BusEvent _, $Res Function(BusEvent) __);
}


/// Adds pattern-matching-related methods to [BusEvent].
extension BusEventPatterns on BusEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusEvent_Echoed value)?  echoed,TResult Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult Function( BusEvent_ConnectionError value)?  connectionError,TResult Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,TResult Function( BusEvent_AutoLockLocked value)?  autoLockLocked,TResult Function( BusEvent_AutoLockUnlocked value)?  autoLockUnlocked,TResult Function( BusEvent_AutoLockTimeoutChanged value)?  autoLockTimeoutChanged,TResult Function( BusEvent_RecorderStarted value)?  recorderStarted,TResult Function( BusEvent_RecorderStopped value)?  recorderStopped,TResult Function( BusEvent_RecorderBytesWritten value)?  recorderBytesWritten,TResult Function( BusEvent_TransferTaskAdded value)?  transferTaskAdded,TResult Function( BusEvent_TransferTaskState value)?  transferTaskState,TResult Function( BusEvent_TransferTaskProgress value)?  transferTaskProgress,TResult Function( BusEvent_TransferTaskError value)?  transferTaskError,TResult Function( BusEvent_PortForwardRegistered value)?  portForwardRegistered,TResult Function( BusEvent_PortForwardStatus value)?  portForwardStatus,TResult Function( BusEvent_PortForwardRemoved value)?  portForwardRemoved,TResult Function( BusEvent_UpdateDownloadProgress value)?  updateDownloadProgress,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusEvent_Echoed value)  echoed,required TResult Function( BusEvent_ConnectionStateChanged value)  connectionStateChanged,required TResult Function( BusEvent_ConnectionProgress value)  connectionProgress,required TResult Function( BusEvent_ConnectionError value)  connectionError,required TResult Function( BusEvent_ConnectionRemoved value)  connectionRemoved,required TResult Function( BusEvent_AutoLockLocked value)  autoLockLocked,required TResult Function( BusEvent_AutoLockUnlocked value)  autoLockUnlocked,required TResult Function( BusEvent_AutoLockTimeoutChanged value)  autoLockTimeoutChanged,required TResult Function( BusEvent_RecorderStarted value)  recorderStarted,required TResult Function( BusEvent_RecorderStopped value)  recorderStopped,required TResult Function( BusEvent_RecorderBytesWritten value)  recorderBytesWritten,required TResult Function( BusEvent_TransferTaskAdded value)  transferTaskAdded,required TResult Function( BusEvent_TransferTaskState value)  transferTaskState,required TResult Function( BusEvent_TransferTaskProgress value)  transferTaskProgress,required TResult Function( BusEvent_TransferTaskError value)  transferTaskError,required TResult Function( BusEvent_PortForwardRegistered value)  portForwardRegistered,required TResult Function( BusEvent_PortForwardStatus value)  portForwardStatus,required TResult Function( BusEvent_PortForwardRemoved value)  portForwardRemoved,required TResult Function( BusEvent_UpdateDownloadProgress value)  updateDownloadProgress,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that);case BusEvent_ConnectionProgress():
return connectionProgress(_that);case BusEvent_ConnectionError():
return connectionError(_that);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that);case BusEvent_AutoLockLocked():
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked():
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged():
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted():
return recorderStarted(_that);case BusEvent_RecorderStopped():
return recorderStopped(_that);case BusEvent_RecorderBytesWritten():
return recorderBytesWritten(_that);case BusEvent_TransferTaskAdded():
return transferTaskAdded(_that);case BusEvent_TransferTaskState():
return transferTaskState(_that);case BusEvent_TransferTaskProgress():
return transferTaskProgress(_that);case BusEvent_TransferTaskError():
return transferTaskError(_that);case BusEvent_PortForwardRegistered():
return portForwardRegistered(_that);case BusEvent_PortForwardStatus():
return portForwardStatus(_that);case BusEvent_PortForwardRemoved():
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress():
return updateDownloadProgress(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusEvent_Echoed value)?  echoed,TResult? Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult? Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult? Function( BusEvent_ConnectionError value)?  connectionError,TResult? Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,TResult? Function( BusEvent_AutoLockLocked value)?  autoLockLocked,TResult? Function( BusEvent_AutoLockUnlocked value)?  autoLockUnlocked,TResult? Function( BusEvent_AutoLockTimeoutChanged value)?  autoLockTimeoutChanged,TResult? Function( BusEvent_RecorderStarted value)?  recorderStarted,TResult? Function( BusEvent_RecorderStopped value)?  recorderStopped,TResult? Function( BusEvent_RecorderBytesWritten value)?  recorderBytesWritten,TResult? Function( BusEvent_TransferTaskAdded value)?  transferTaskAdded,TResult? Function( BusEvent_TransferTaskState value)?  transferTaskState,TResult? Function( BusEvent_TransferTaskProgress value)?  transferTaskProgress,TResult? Function( BusEvent_TransferTaskError value)?  transferTaskError,TResult? Function( BusEvent_PortForwardRegistered value)?  portForwardRegistered,TResult? Function( BusEvent_PortForwardStatus value)?  portForwardStatus,TResult? Function( BusEvent_PortForwardRemoved value)?  portForwardRemoved,TResult? Function( BusEvent_UpdateDownloadProgress value)?  updateDownloadProgress,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  echoed,TResult Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult Function( String id,  BusProgressStep step)?  connectionProgress,TResult Function( String id,  String detail)?  connectionError,TResult Function( String id)?  connectionRemoved,TResult Function()?  autoLockLocked,TResult Function()?  autoLockUnlocked,TResult Function( PlatformInt64 minutes)?  autoLockTimeoutChanged,TResult Function( String id,  String path)?  recorderStarted,TResult Function( String id)?  recorderStopped,TResult Function( String id,  BigInt totalBytes)?  recorderBytesWritten,TResult Function( String id)?  transferTaskAdded,TResult Function( String id,  BusTaskState state)?  transferTaskState,TResult Function( String id,  BigInt bytesDone,  BigInt bytesTotal)?  transferTaskProgress,TResult Function( String id,  String detail)?  transferTaskError,TResult Function( String id)?  portForwardRegistered,TResult Function( String id,  BusRuleStatus status,  String? detail)?  portForwardStatus,TResult Function( String id)?  portForwardRemoved,TResult Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)?  updateDownloadProgress,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked();case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  echoed,required TResult Function( String id,  BusConnectionState state)  connectionStateChanged,required TResult Function( String id,  BusProgressStep step)  connectionProgress,required TResult Function( String id,  String detail)  connectionError,required TResult Function( String id)  connectionRemoved,required TResult Function()  autoLockLocked,required TResult Function()  autoLockUnlocked,required TResult Function( PlatformInt64 minutes)  autoLockTimeoutChanged,required TResult Function( String id,  String path)  recorderStarted,required TResult Function( String id)  recorderStopped,required TResult Function( String id,  BigInt totalBytes)  recorderBytesWritten,required TResult Function( String id)  transferTaskAdded,required TResult Function( String id,  BusTaskState state)  transferTaskState,required TResult Function( String id,  BigInt bytesDone,  BigInt bytesTotal)  transferTaskProgress,required TResult Function( String id,  String detail)  transferTaskError,required TResult Function( String id)  portForwardRegistered,required TResult Function( String id,  BusRuleStatus status,  String? detail)  portForwardStatus,required TResult Function( String id)  portForwardRemoved,required TResult Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)  updateDownloadProgress,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that.payload);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress():
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError():
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that.id);case BusEvent_AutoLockLocked():
return autoLockLocked();case BusEvent_AutoLockUnlocked():
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged():
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted():
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped():
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten():
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_TransferTaskAdded():
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState():
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress():
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError():
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered():
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus():
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved():
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress():
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  echoed,TResult? Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult? Function( String id,  BusProgressStep step)?  connectionProgress,TResult? Function( String id,  String detail)?  connectionError,TResult? Function( String id)?  connectionRemoved,TResult? Function()?  autoLockLocked,TResult? Function()?  autoLockUnlocked,TResult? Function( PlatformInt64 minutes)?  autoLockTimeoutChanged,TResult? Function( String id,  String path)?  recorderStarted,TResult? Function( String id)?  recorderStopped,TResult? Function( String id,  BigInt totalBytes)?  recorderBytesWritten,TResult? Function( String id)?  transferTaskAdded,TResult? Function( String id,  BusTaskState state)?  transferTaskState,TResult? Function( String id,  BigInt bytesDone,  BigInt bytesTotal)?  transferTaskProgress,TResult? Function( String id,  String detail)?  transferTaskError,TResult? Function( String id)?  portForwardRegistered,TResult? Function( String id,  BusRuleStatus status,  String? detail)?  portForwardStatus,TResult? Function( String id)?  portForwardRemoved,TResult? Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)?  updateDownloadProgress,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked();case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);case _:
  return null;

}
}

}

/// @nodoc


class BusEvent_Echoed extends BusEvent {
  const BusEvent_Echoed({required this.payload}): super._();
  

 final  String payload;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_EchoedCopyWith<BusEvent_Echoed> get copyWith => _$BusEvent_EchoedCopyWithImpl<BusEvent_Echoed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_Echoed&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,payload);

@override
String toString() {
  return 'BusEvent.echoed(payload: $payload)';
}


}

/// @nodoc
abstract mixin class $BusEvent_EchoedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_EchoedCopyWith(BusEvent_Echoed value, $Res Function(BusEvent_Echoed) _then) = _$BusEvent_EchoedCopyWithImpl;
@useResult
$Res call({
 String payload
});




}
/// @nodoc
class _$BusEvent_EchoedCopyWithImpl<$Res>
    implements $BusEvent_EchoedCopyWith<$Res> {
  _$BusEvent_EchoedCopyWithImpl(this._self, this._then);

  final BusEvent_Echoed _self;
  final $Res Function(BusEvent_Echoed) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? payload = null,}) {
  return _then(BusEvent_Echoed(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_ConnectionStateChanged extends BusEvent {
  const BusEvent_ConnectionStateChanged({required this.id, required this.state}): super._();
  

 final  String id;
 final  BusConnectionState state;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConnectionStateChangedCopyWith<BusEvent_ConnectionStateChanged> get copyWith => _$BusEvent_ConnectionStateChangedCopyWithImpl<BusEvent_ConnectionStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConnectionStateChanged&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,id,state);

@override
String toString() {
  return 'BusEvent.connectionStateChanged(id: $id, state: $state)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConnectionStateChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConnectionStateChangedCopyWith(BusEvent_ConnectionStateChanged value, $Res Function(BusEvent_ConnectionStateChanged) _then) = _$BusEvent_ConnectionStateChangedCopyWithImpl;
@useResult
$Res call({
 String id, BusConnectionState state
});




}
/// @nodoc
class _$BusEvent_ConnectionStateChangedCopyWithImpl<$Res>
    implements $BusEvent_ConnectionStateChangedCopyWith<$Res> {
  _$BusEvent_ConnectionStateChangedCopyWithImpl(this._self, this._then);

  final BusEvent_ConnectionStateChanged _self;
  final $Res Function(BusEvent_ConnectionStateChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? state = null,}) {
  return _then(BusEvent_ConnectionStateChanged(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BusConnectionState,
  ));
}


}

/// @nodoc


class BusEvent_ConnectionProgress extends BusEvent {
  const BusEvent_ConnectionProgress({required this.id, required this.step}): super._();
  

 final  String id;
 final  BusProgressStep step;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConnectionProgressCopyWith<BusEvent_ConnectionProgress> get copyWith => _$BusEvent_ConnectionProgressCopyWithImpl<BusEvent_ConnectionProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConnectionProgress&&(identical(other.id, id) || other.id == id)&&(identical(other.step, step) || other.step == step));
}


@override
int get hashCode => Object.hash(runtimeType,id,step);

@override
String toString() {
  return 'BusEvent.connectionProgress(id: $id, step: $step)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConnectionProgressCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConnectionProgressCopyWith(BusEvent_ConnectionProgress value, $Res Function(BusEvent_ConnectionProgress) _then) = _$BusEvent_ConnectionProgressCopyWithImpl;
@useResult
$Res call({
 String id, BusProgressStep step
});




}
/// @nodoc
class _$BusEvent_ConnectionProgressCopyWithImpl<$Res>
    implements $BusEvent_ConnectionProgressCopyWith<$Res> {
  _$BusEvent_ConnectionProgressCopyWithImpl(this._self, this._then);

  final BusEvent_ConnectionProgress _self;
  final $Res Function(BusEvent_ConnectionProgress) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? step = null,}) {
  return _then(BusEvent_ConnectionProgress(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as BusProgressStep,
  ));
}


}

/// @nodoc


class BusEvent_ConnectionError extends BusEvent {
  const BusEvent_ConnectionError({required this.id, required this.detail}): super._();
  

 final  String id;
 final  String detail;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConnectionErrorCopyWith<BusEvent_ConnectionError> get copyWith => _$BusEvent_ConnectionErrorCopyWithImpl<BusEvent_ConnectionError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConnectionError&&(identical(other.id, id) || other.id == id)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,id,detail);

@override
String toString() {
  return 'BusEvent.connectionError(id: $id, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConnectionErrorCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConnectionErrorCopyWith(BusEvent_ConnectionError value, $Res Function(BusEvent_ConnectionError) _then) = _$BusEvent_ConnectionErrorCopyWithImpl;
@useResult
$Res call({
 String id, String detail
});




}
/// @nodoc
class _$BusEvent_ConnectionErrorCopyWithImpl<$Res>
    implements $BusEvent_ConnectionErrorCopyWith<$Res> {
  _$BusEvent_ConnectionErrorCopyWithImpl(this._self, this._then);

  final BusEvent_ConnectionError _self;
  final $Res Function(BusEvent_ConnectionError) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? detail = null,}) {
  return _then(BusEvent_ConnectionError(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_ConnectionRemoved extends BusEvent {
  const BusEvent_ConnectionRemoved({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConnectionRemovedCopyWith<BusEvent_ConnectionRemoved> get copyWith => _$BusEvent_ConnectionRemovedCopyWithImpl<BusEvent_ConnectionRemoved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConnectionRemoved&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusEvent.connectionRemoved(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConnectionRemovedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConnectionRemovedCopyWith(BusEvent_ConnectionRemoved value, $Res Function(BusEvent_ConnectionRemoved) _then) = _$BusEvent_ConnectionRemovedCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusEvent_ConnectionRemovedCopyWithImpl<$Res>
    implements $BusEvent_ConnectionRemovedCopyWith<$Res> {
  _$BusEvent_ConnectionRemovedCopyWithImpl(this._self, this._then);

  final BusEvent_ConnectionRemoved _self;
  final $Res Function(BusEvent_ConnectionRemoved) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusEvent_ConnectionRemoved(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_AutoLockLocked extends BusEvent {
  const BusEvent_AutoLockLocked(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_AutoLockLocked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusEvent.autoLockLocked()';
}


}




/// @nodoc


class BusEvent_AutoLockUnlocked extends BusEvent {
  const BusEvent_AutoLockUnlocked(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_AutoLockUnlocked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusEvent.autoLockUnlocked()';
}


}




/// @nodoc


class BusEvent_AutoLockTimeoutChanged extends BusEvent {
  const BusEvent_AutoLockTimeoutChanged({required this.minutes}): super._();
  

 final  PlatformInt64 minutes;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_AutoLockTimeoutChangedCopyWith<BusEvent_AutoLockTimeoutChanged> get copyWith => _$BusEvent_AutoLockTimeoutChangedCopyWithImpl<BusEvent_AutoLockTimeoutChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_AutoLockTimeoutChanged&&(identical(other.minutes, minutes) || other.minutes == minutes));
}


@override
int get hashCode => Object.hash(runtimeType,minutes);

@override
String toString() {
  return 'BusEvent.autoLockTimeoutChanged(minutes: $minutes)';
}


}

/// @nodoc
abstract mixin class $BusEvent_AutoLockTimeoutChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_AutoLockTimeoutChangedCopyWith(BusEvent_AutoLockTimeoutChanged value, $Res Function(BusEvent_AutoLockTimeoutChanged) _then) = _$BusEvent_AutoLockTimeoutChangedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 minutes
});




}
/// @nodoc
class _$BusEvent_AutoLockTimeoutChangedCopyWithImpl<$Res>
    implements $BusEvent_AutoLockTimeoutChangedCopyWith<$Res> {
  _$BusEvent_AutoLockTimeoutChangedCopyWithImpl(this._self, this._then);

  final BusEvent_AutoLockTimeoutChanged _self;
  final $Res Function(BusEvent_AutoLockTimeoutChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? minutes = null,}) {
  return _then(BusEvent_AutoLockTimeoutChanged(
minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BusEvent_RecorderStarted extends BusEvent {
  const BusEvent_RecorderStarted({required this.id, required this.path}): super._();
  

 final  String id;
 final  String path;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_RecorderStartedCopyWith<BusEvent_RecorderStarted> get copyWith => _$BusEvent_RecorderStartedCopyWithImpl<BusEvent_RecorderStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_RecorderStarted&&(identical(other.id, id) || other.id == id)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,id,path);

@override
String toString() {
  return 'BusEvent.recorderStarted(id: $id, path: $path)';
}


}

/// @nodoc
abstract mixin class $BusEvent_RecorderStartedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_RecorderStartedCopyWith(BusEvent_RecorderStarted value, $Res Function(BusEvent_RecorderStarted) _then) = _$BusEvent_RecorderStartedCopyWithImpl;
@useResult
$Res call({
 String id, String path
});




}
/// @nodoc
class _$BusEvent_RecorderStartedCopyWithImpl<$Res>
    implements $BusEvent_RecorderStartedCopyWith<$Res> {
  _$BusEvent_RecorderStartedCopyWithImpl(this._self, this._then);

  final BusEvent_RecorderStarted _self;
  final $Res Function(BusEvent_RecorderStarted) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? path = null,}) {
  return _then(BusEvent_RecorderStarted(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_RecorderStopped extends BusEvent {
  const BusEvent_RecorderStopped({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_RecorderStoppedCopyWith<BusEvent_RecorderStopped> get copyWith => _$BusEvent_RecorderStoppedCopyWithImpl<BusEvent_RecorderStopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_RecorderStopped&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusEvent.recorderStopped(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusEvent_RecorderStoppedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_RecorderStoppedCopyWith(BusEvent_RecorderStopped value, $Res Function(BusEvent_RecorderStopped) _then) = _$BusEvent_RecorderStoppedCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusEvent_RecorderStoppedCopyWithImpl<$Res>
    implements $BusEvent_RecorderStoppedCopyWith<$Res> {
  _$BusEvent_RecorderStoppedCopyWithImpl(this._self, this._then);

  final BusEvent_RecorderStopped _self;
  final $Res Function(BusEvent_RecorderStopped) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusEvent_RecorderStopped(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_RecorderBytesWritten extends BusEvent {
  const BusEvent_RecorderBytesWritten({required this.id, required this.totalBytes}): super._();
  

 final  String id;
 final  BigInt totalBytes;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_RecorderBytesWrittenCopyWith<BusEvent_RecorderBytesWritten> get copyWith => _$BusEvent_RecorderBytesWrittenCopyWithImpl<BusEvent_RecorderBytesWritten>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_RecorderBytesWritten&&(identical(other.id, id) || other.id == id)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes));
}


@override
int get hashCode => Object.hash(runtimeType,id,totalBytes);

@override
String toString() {
  return 'BusEvent.recorderBytesWritten(id: $id, totalBytes: $totalBytes)';
}


}

/// @nodoc
abstract mixin class $BusEvent_RecorderBytesWrittenCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_RecorderBytesWrittenCopyWith(BusEvent_RecorderBytesWritten value, $Res Function(BusEvent_RecorderBytesWritten) _then) = _$BusEvent_RecorderBytesWrittenCopyWithImpl;
@useResult
$Res call({
 String id, BigInt totalBytes
});




}
/// @nodoc
class _$BusEvent_RecorderBytesWrittenCopyWithImpl<$Res>
    implements $BusEvent_RecorderBytesWrittenCopyWith<$Res> {
  _$BusEvent_RecorderBytesWrittenCopyWithImpl(this._self, this._then);

  final BusEvent_RecorderBytesWritten _self;
  final $Res Function(BusEvent_RecorderBytesWritten) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? totalBytes = null,}) {
  return _then(BusEvent_RecorderBytesWritten(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BusEvent_TransferTaskAdded extends BusEvent {
  const BusEvent_TransferTaskAdded({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_TransferTaskAddedCopyWith<BusEvent_TransferTaskAdded> get copyWith => _$BusEvent_TransferTaskAddedCopyWithImpl<BusEvent_TransferTaskAdded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_TransferTaskAdded&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusEvent.transferTaskAdded(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusEvent_TransferTaskAddedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_TransferTaskAddedCopyWith(BusEvent_TransferTaskAdded value, $Res Function(BusEvent_TransferTaskAdded) _then) = _$BusEvent_TransferTaskAddedCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusEvent_TransferTaskAddedCopyWithImpl<$Res>
    implements $BusEvent_TransferTaskAddedCopyWith<$Res> {
  _$BusEvent_TransferTaskAddedCopyWithImpl(this._self, this._then);

  final BusEvent_TransferTaskAdded _self;
  final $Res Function(BusEvent_TransferTaskAdded) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusEvent_TransferTaskAdded(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_TransferTaskState extends BusEvent {
  const BusEvent_TransferTaskState({required this.id, required this.state}): super._();
  

 final  String id;
 final  BusTaskState state;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_TransferTaskStateCopyWith<BusEvent_TransferTaskState> get copyWith => _$BusEvent_TransferTaskStateCopyWithImpl<BusEvent_TransferTaskState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_TransferTaskState&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,id,state);

@override
String toString() {
  return 'BusEvent.transferTaskState(id: $id, state: $state)';
}


}

/// @nodoc
abstract mixin class $BusEvent_TransferTaskStateCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_TransferTaskStateCopyWith(BusEvent_TransferTaskState value, $Res Function(BusEvent_TransferTaskState) _then) = _$BusEvent_TransferTaskStateCopyWithImpl;
@useResult
$Res call({
 String id, BusTaskState state
});




}
/// @nodoc
class _$BusEvent_TransferTaskStateCopyWithImpl<$Res>
    implements $BusEvent_TransferTaskStateCopyWith<$Res> {
  _$BusEvent_TransferTaskStateCopyWithImpl(this._self, this._then);

  final BusEvent_TransferTaskState _self;
  final $Res Function(BusEvent_TransferTaskState) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? state = null,}) {
  return _then(BusEvent_TransferTaskState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BusTaskState,
  ));
}


}

/// @nodoc


class BusEvent_TransferTaskProgress extends BusEvent {
  const BusEvent_TransferTaskProgress({required this.id, required this.bytesDone, required this.bytesTotal}): super._();
  

 final  String id;
 final  BigInt bytesDone;
 final  BigInt bytesTotal;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_TransferTaskProgressCopyWith<BusEvent_TransferTaskProgress> get copyWith => _$BusEvent_TransferTaskProgressCopyWithImpl<BusEvent_TransferTaskProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_TransferTaskProgress&&(identical(other.id, id) || other.id == id)&&(identical(other.bytesDone, bytesDone) || other.bytesDone == bytesDone)&&(identical(other.bytesTotal, bytesTotal) || other.bytesTotal == bytesTotal));
}


@override
int get hashCode => Object.hash(runtimeType,id,bytesDone,bytesTotal);

@override
String toString() {
  return 'BusEvent.transferTaskProgress(id: $id, bytesDone: $bytesDone, bytesTotal: $bytesTotal)';
}


}

/// @nodoc
abstract mixin class $BusEvent_TransferTaskProgressCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_TransferTaskProgressCopyWith(BusEvent_TransferTaskProgress value, $Res Function(BusEvent_TransferTaskProgress) _then) = _$BusEvent_TransferTaskProgressCopyWithImpl;
@useResult
$Res call({
 String id, BigInt bytesDone, BigInt bytesTotal
});




}
/// @nodoc
class _$BusEvent_TransferTaskProgressCopyWithImpl<$Res>
    implements $BusEvent_TransferTaskProgressCopyWith<$Res> {
  _$BusEvent_TransferTaskProgressCopyWithImpl(this._self, this._then);

  final BusEvent_TransferTaskProgress _self;
  final $Res Function(BusEvent_TransferTaskProgress) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bytesDone = null,Object? bytesTotal = null,}) {
  return _then(BusEvent_TransferTaskProgress(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bytesDone: null == bytesDone ? _self.bytesDone : bytesDone // ignore: cast_nullable_to_non_nullable
as BigInt,bytesTotal: null == bytesTotal ? _self.bytesTotal : bytesTotal // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BusEvent_TransferTaskError extends BusEvent {
  const BusEvent_TransferTaskError({required this.id, required this.detail}): super._();
  

 final  String id;
 final  String detail;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_TransferTaskErrorCopyWith<BusEvent_TransferTaskError> get copyWith => _$BusEvent_TransferTaskErrorCopyWithImpl<BusEvent_TransferTaskError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_TransferTaskError&&(identical(other.id, id) || other.id == id)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,id,detail);

@override
String toString() {
  return 'BusEvent.transferTaskError(id: $id, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BusEvent_TransferTaskErrorCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_TransferTaskErrorCopyWith(BusEvent_TransferTaskError value, $Res Function(BusEvent_TransferTaskError) _then) = _$BusEvent_TransferTaskErrorCopyWithImpl;
@useResult
$Res call({
 String id, String detail
});




}
/// @nodoc
class _$BusEvent_TransferTaskErrorCopyWithImpl<$Res>
    implements $BusEvent_TransferTaskErrorCopyWith<$Res> {
  _$BusEvent_TransferTaskErrorCopyWithImpl(this._self, this._then);

  final BusEvent_TransferTaskError _self;
  final $Res Function(BusEvent_TransferTaskError) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? detail = null,}) {
  return _then(BusEvent_TransferTaskError(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_PortForwardRegistered extends BusEvent {
  const BusEvent_PortForwardRegistered({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_PortForwardRegisteredCopyWith<BusEvent_PortForwardRegistered> get copyWith => _$BusEvent_PortForwardRegisteredCopyWithImpl<BusEvent_PortForwardRegistered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_PortForwardRegistered&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusEvent.portForwardRegistered(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusEvent_PortForwardRegisteredCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_PortForwardRegisteredCopyWith(BusEvent_PortForwardRegistered value, $Res Function(BusEvent_PortForwardRegistered) _then) = _$BusEvent_PortForwardRegisteredCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusEvent_PortForwardRegisteredCopyWithImpl<$Res>
    implements $BusEvent_PortForwardRegisteredCopyWith<$Res> {
  _$BusEvent_PortForwardRegisteredCopyWithImpl(this._self, this._then);

  final BusEvent_PortForwardRegistered _self;
  final $Res Function(BusEvent_PortForwardRegistered) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusEvent_PortForwardRegistered(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_PortForwardStatus extends BusEvent {
  const BusEvent_PortForwardStatus({required this.id, required this.status, this.detail}): super._();
  

 final  String id;
 final  BusRuleStatus status;
 final  String? detail;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_PortForwardStatusCopyWith<BusEvent_PortForwardStatus> get copyWith => _$BusEvent_PortForwardStatusCopyWithImpl<BusEvent_PortForwardStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_PortForwardStatus&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,id,status,detail);

@override
String toString() {
  return 'BusEvent.portForwardStatus(id: $id, status: $status, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BusEvent_PortForwardStatusCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_PortForwardStatusCopyWith(BusEvent_PortForwardStatus value, $Res Function(BusEvent_PortForwardStatus) _then) = _$BusEvent_PortForwardStatusCopyWithImpl;
@useResult
$Res call({
 String id, BusRuleStatus status, String? detail
});




}
/// @nodoc
class _$BusEvent_PortForwardStatusCopyWithImpl<$Res>
    implements $BusEvent_PortForwardStatusCopyWith<$Res> {
  _$BusEvent_PortForwardStatusCopyWithImpl(this._self, this._then);

  final BusEvent_PortForwardStatus _self;
  final $Res Function(BusEvent_PortForwardStatus) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,Object? detail = freezed,}) {
  return _then(BusEvent_PortForwardStatus(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BusRuleStatus,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BusEvent_PortForwardRemoved extends BusEvent {
  const BusEvent_PortForwardRemoved({required this.id}): super._();
  

 final  String id;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_PortForwardRemovedCopyWith<BusEvent_PortForwardRemoved> get copyWith => _$BusEvent_PortForwardRemovedCopyWithImpl<BusEvent_PortForwardRemoved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_PortForwardRemoved&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BusEvent.portForwardRemoved(id: $id)';
}


}

/// @nodoc
abstract mixin class $BusEvent_PortForwardRemovedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_PortForwardRemovedCopyWith(BusEvent_PortForwardRemoved value, $Res Function(BusEvent_PortForwardRemoved) _then) = _$BusEvent_PortForwardRemovedCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BusEvent_PortForwardRemovedCopyWithImpl<$Res>
    implements $BusEvent_PortForwardRemovedCopyWith<$Res> {
  _$BusEvent_PortForwardRemovedCopyWithImpl(this._self, this._then);

  final BusEvent_PortForwardRemoved _self;
  final $Res Function(BusEvent_PortForwardRemoved) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BusEvent_PortForwardRemoved(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_UpdateDownloadProgress extends BusEvent {
  const BusEvent_UpdateDownloadProgress({required this.url, required this.writtenBytes, this.totalBytes}): super._();
  

 final  String url;
 final  BigInt writtenBytes;
 final  BigInt? totalBytes;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_UpdateDownloadProgressCopyWith<BusEvent_UpdateDownloadProgress> get copyWith => _$BusEvent_UpdateDownloadProgressCopyWithImpl<BusEvent_UpdateDownloadProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_UpdateDownloadProgress&&(identical(other.url, url) || other.url == url)&&(identical(other.writtenBytes, writtenBytes) || other.writtenBytes == writtenBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes));
}


@override
int get hashCode => Object.hash(runtimeType,url,writtenBytes,totalBytes);

@override
String toString() {
  return 'BusEvent.updateDownloadProgress(url: $url, writtenBytes: $writtenBytes, totalBytes: $totalBytes)';
}


}

/// @nodoc
abstract mixin class $BusEvent_UpdateDownloadProgressCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_UpdateDownloadProgressCopyWith(BusEvent_UpdateDownloadProgress value, $Res Function(BusEvent_UpdateDownloadProgress) _then) = _$BusEvent_UpdateDownloadProgressCopyWithImpl;
@useResult
$Res call({
 String url, BigInt writtenBytes, BigInt? totalBytes
});




}
/// @nodoc
class _$BusEvent_UpdateDownloadProgressCopyWithImpl<$Res>
    implements $BusEvent_UpdateDownloadProgressCopyWith<$Res> {
  _$BusEvent_UpdateDownloadProgressCopyWithImpl(this._self, this._then);

  final BusEvent_UpdateDownloadProgress _self;
  final $Res Function(BusEvent_UpdateDownloadProgress) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? writtenBytes = null,Object? totalBytes = freezed,}) {
  return _then(BusEvent_UpdateDownloadProgress(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,writtenBytes: null == writtenBytes ? _self.writtenBytes : writtenBytes // ignore: cast_nullable_to_non_nullable
as BigInt,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

// dart format on
