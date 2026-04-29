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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusCommand_NoopEcho value)?  noopEcho,TResult Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,TResult Function( BusCommand_ConnectionDisconnectAll value)?  connectionDisconnectAll,TResult Function( BusCommand_AutoLockOnPointerActivity value)?  autoLockOnPointerActivity,TResult Function( BusCommand_AutoLockOnLifecycleChange value)?  autoLockOnLifecycleChange,TResult Function( BusCommand_AutoLockSetTimeout value)?  autoLockSetTimeout,TResult Function( BusCommand_AutoLockRequestLock value)?  autoLockRequestLock,TResult Function( BusCommand_AutoLockUnlock value)?  autoLockUnlock,TResult Function( BusCommand_KnownHostPromptResponse value)?  knownHostPromptResponse,required TResult orElse(),}){
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
return autoLockUnlock(_that);case BusCommand_KnownHostPromptResponse() when knownHostPromptResponse != null:
return knownHostPromptResponse(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusCommand_NoopEcho value)  noopEcho,required TResult Function( BusCommand_ConnectionDisconnect value)  connectionDisconnect,required TResult Function( BusCommand_ConnectionDisconnectAll value)  connectionDisconnectAll,required TResult Function( BusCommand_AutoLockOnPointerActivity value)  autoLockOnPointerActivity,required TResult Function( BusCommand_AutoLockOnLifecycleChange value)  autoLockOnLifecycleChange,required TResult Function( BusCommand_AutoLockSetTimeout value)  autoLockSetTimeout,required TResult Function( BusCommand_AutoLockRequestLock value)  autoLockRequestLock,required TResult Function( BusCommand_AutoLockUnlock value)  autoLockUnlock,required TResult Function( BusCommand_KnownHostPromptResponse value)  knownHostPromptResponse,}){
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
return autoLockUnlock(_that);case BusCommand_KnownHostPromptResponse():
return knownHostPromptResponse(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusCommand_NoopEcho value)?  noopEcho,TResult? Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,TResult? Function( BusCommand_ConnectionDisconnectAll value)?  connectionDisconnectAll,TResult? Function( BusCommand_AutoLockOnPointerActivity value)?  autoLockOnPointerActivity,TResult? Function( BusCommand_AutoLockOnLifecycleChange value)?  autoLockOnLifecycleChange,TResult? Function( BusCommand_AutoLockSetTimeout value)?  autoLockSetTimeout,TResult? Function( BusCommand_AutoLockRequestLock value)?  autoLockRequestLock,TResult? Function( BusCommand_AutoLockUnlock value)?  autoLockUnlock,TResult? Function( BusCommand_KnownHostPromptResponse value)?  knownHostPromptResponse,}){
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
return autoLockUnlock(_that);case BusCommand_KnownHostPromptResponse() when knownHostPromptResponse != null:
return knownHostPromptResponse(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  noopEcho,TResult Function( String id)?  connectionDisconnect,TResult Function()?  connectionDisconnectAll,TResult Function()?  autoLockOnPointerActivity,TResult Function( bool background)?  autoLockOnLifecycleChange,TResult Function( PlatformInt64 minutes)?  autoLockSetTimeout,TResult Function()?  autoLockRequestLock,TResult Function()?  autoLockUnlock,TResult Function( String promptId,  bool accepted)?  knownHostPromptResponse,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock();case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock();case BusCommand_KnownHostPromptResponse() when knownHostPromptResponse != null:
return knownHostPromptResponse(_that.promptId,_that.accepted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  noopEcho,required TResult Function( String id)  connectionDisconnect,required TResult Function()  connectionDisconnectAll,required TResult Function()  autoLockOnPointerActivity,required TResult Function( bool background)  autoLockOnLifecycleChange,required TResult Function( PlatformInt64 minutes)  autoLockSetTimeout,required TResult Function()  autoLockRequestLock,required TResult Function()  autoLockUnlock,required TResult Function( String promptId,  bool accepted)  knownHostPromptResponse,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect():
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll():
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity():
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange():
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout():
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock():
return autoLockRequestLock();case BusCommand_AutoLockUnlock():
return autoLockUnlock();case BusCommand_KnownHostPromptResponse():
return knownHostPromptResponse(_that.promptId,_that.accepted);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  noopEcho,TResult? Function( String id)?  connectionDisconnect,TResult? Function()?  connectionDisconnectAll,TResult? Function()?  autoLockOnPointerActivity,TResult? Function( bool background)?  autoLockOnLifecycleChange,TResult? Function( PlatformInt64 minutes)?  autoLockSetTimeout,TResult? Function()?  autoLockRequestLock,TResult? Function()?  autoLockUnlock,TResult? Function( String promptId,  bool accepted)?  knownHostPromptResponse,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case BusCommand_ConnectionDisconnectAll() when connectionDisconnectAll != null:
return connectionDisconnectAll();case BusCommand_AutoLockOnPointerActivity() when autoLockOnPointerActivity != null:
return autoLockOnPointerActivity();case BusCommand_AutoLockOnLifecycleChange() when autoLockOnLifecycleChange != null:
return autoLockOnLifecycleChange(_that.background);case BusCommand_AutoLockSetTimeout() when autoLockSetTimeout != null:
return autoLockSetTimeout(_that.minutes);case BusCommand_AutoLockRequestLock() when autoLockRequestLock != null:
return autoLockRequestLock();case BusCommand_AutoLockUnlock() when autoLockUnlock != null:
return autoLockUnlock();case BusCommand_KnownHostPromptResponse() when knownHostPromptResponse != null:
return knownHostPromptResponse(_that.promptId,_that.accepted);case _:
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


class BusCommand_KnownHostPromptResponse extends BusCommand {
  const BusCommand_KnownHostPromptResponse({required this.promptId, required this.accepted}): super._();
  

 final  String promptId;
 final  bool accepted;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommand_KnownHostPromptResponseCopyWith<BusCommand_KnownHostPromptResponse> get copyWith => _$BusCommand_KnownHostPromptResponseCopyWithImpl<BusCommand_KnownHostPromptResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand_KnownHostPromptResponse&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.accepted, accepted) || other.accepted == accepted));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,accepted);

@override
String toString() {
  return 'BusCommand.knownHostPromptResponse(promptId: $promptId, accepted: $accepted)';
}


}

/// @nodoc
abstract mixin class $BusCommand_KnownHostPromptResponseCopyWith<$Res> implements $BusCommandCopyWith<$Res> {
  factory $BusCommand_KnownHostPromptResponseCopyWith(BusCommand_KnownHostPromptResponse value, $Res Function(BusCommand_KnownHostPromptResponse) _then) = _$BusCommand_KnownHostPromptResponseCopyWithImpl;
@useResult
$Res call({
 String promptId, bool accepted
});




}
/// @nodoc
class _$BusCommand_KnownHostPromptResponseCopyWithImpl<$Res>
    implements $BusCommand_KnownHostPromptResponseCopyWith<$Res> {
  _$BusCommand_KnownHostPromptResponseCopyWithImpl(this._self, this._then);

  final BusCommand_KnownHostPromptResponse _self;
  final $Res Function(BusCommand_KnownHostPromptResponse) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? accepted = null,}) {
  return _then(BusCommand_KnownHostPromptResponse(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusEvent_Echoed value)?  echoed,TResult Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult Function( BusEvent_ConnectionError value)?  connectionError,TResult Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,TResult Function( BusEvent_ConnectionActiveCountChanged value)?  connectionActiveCountChanged,TResult Function( BusEvent_AutoLockLocked value)?  autoLockLocked,TResult Function( BusEvent_AutoLockUnlocked value)?  autoLockUnlocked,TResult Function( BusEvent_AutoLockTimeoutChanged value)?  autoLockTimeoutChanged,TResult Function( BusEvent_RecorderStarted value)?  recorderStarted,TResult Function( BusEvent_RecorderStopped value)?  recorderStopped,TResult Function( BusEvent_RecorderBytesWritten value)?  recorderBytesWritten,TResult Function( BusEvent_RecorderRotateRequested value)?  recorderRotateRequested,TResult Function( BusEvent_TransferTaskAdded value)?  transferTaskAdded,TResult Function( BusEvent_TransferTaskState value)?  transferTaskState,TResult Function( BusEvent_TransferTaskProgress value)?  transferTaskProgress,TResult Function( BusEvent_TransferTaskError value)?  transferTaskError,TResult Function( BusEvent_PortForwardRegistered value)?  portForwardRegistered,TResult Function( BusEvent_PortForwardStatus value)?  portForwardStatus,TResult Function( BusEvent_PortForwardRemoved value)?  portForwardRemoved,TResult Function( BusEvent_UpdateDownloadProgress value)?  updateDownloadProgress,TResult Function( BusEvent_UpdateVerifyingStarted value)?  updateVerifyingStarted,TResult Function( BusEvent_UpdateDownloadCompleted value)?  updateDownloadCompleted,TResult Function( BusEvent_KnownHostsChanged value)?  knownHostsChanged,TResult Function( BusEvent_SessionsChanged value)?  sessionsChanged,TResult Function( BusEvent_ConfigChanged value)?  configChanged,TResult Function( BusEvent_TierStateChanged value)?  tierStateChanged,TResult Function( BusEvent_KeychainPepperPromptRequest value)?  keychainPepperPromptRequest,TResult Function( BusEvent_CredentialPromptRequest value)?  credentialPromptRequest,TResult Function( BusEvent_BiometricProbePromptRequest value)?  biometricProbePromptRequest,TResult Function( BusEvent_KeychainProbePromptRequest value)?  keychainProbePromptRequest,TResult Function( BusEvent_HardwareVaultProbePromptRequest value)?  hardwareVaultProbePromptRequest,TResult Function( BusEvent_HardwareVaultUnlockPromptRequest value)?  hardwareVaultUnlockPromptRequest,TResult Function( BusEvent_KeychainOpPromptRequest value)?  keychainOpPromptRequest,TResult Function( BusEvent_SecurityCapabilitiesChanged value)?  securityCapabilitiesChanged,TResult Function( BusEvent_KnownHostPromptRequest value)?  knownHostPromptRequest,TResult Function( BusEvent_KnownHostPromptResolved value)?  knownHostPromptResolved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case BusEvent_ConnectionActiveCountChanged() when connectionActiveCountChanged != null:
return connectionActiveCountChanged(_that);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that);case BusEvent_RecorderRotateRequested() when recorderRotateRequested != null:
return recorderRotateRequested(_that);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that);case BusEvent_UpdateVerifyingStarted() when updateVerifyingStarted != null:
return updateVerifyingStarted(_that);case BusEvent_UpdateDownloadCompleted() when updateDownloadCompleted != null:
return updateDownloadCompleted(_that);case BusEvent_KnownHostsChanged() when knownHostsChanged != null:
return knownHostsChanged(_that);case BusEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged(_that);case BusEvent_ConfigChanged() when configChanged != null:
return configChanged(_that);case BusEvent_TierStateChanged() when tierStateChanged != null:
return tierStateChanged(_that);case BusEvent_KeychainPepperPromptRequest() when keychainPepperPromptRequest != null:
return keychainPepperPromptRequest(_that);case BusEvent_CredentialPromptRequest() when credentialPromptRequest != null:
return credentialPromptRequest(_that);case BusEvent_BiometricProbePromptRequest() when biometricProbePromptRequest != null:
return biometricProbePromptRequest(_that);case BusEvent_KeychainProbePromptRequest() when keychainProbePromptRequest != null:
return keychainProbePromptRequest(_that);case BusEvent_HardwareVaultProbePromptRequest() when hardwareVaultProbePromptRequest != null:
return hardwareVaultProbePromptRequest(_that);case BusEvent_HardwareVaultUnlockPromptRequest() when hardwareVaultUnlockPromptRequest != null:
return hardwareVaultUnlockPromptRequest(_that);case BusEvent_KeychainOpPromptRequest() when keychainOpPromptRequest != null:
return keychainOpPromptRequest(_that);case BusEvent_SecurityCapabilitiesChanged() when securityCapabilitiesChanged != null:
return securityCapabilitiesChanged(_that);case BusEvent_KnownHostPromptRequest() when knownHostPromptRequest != null:
return knownHostPromptRequest(_that);case BusEvent_KnownHostPromptResolved() when knownHostPromptResolved != null:
return knownHostPromptResolved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusEvent_Echoed value)  echoed,required TResult Function( BusEvent_ConnectionStateChanged value)  connectionStateChanged,required TResult Function( BusEvent_ConnectionProgress value)  connectionProgress,required TResult Function( BusEvent_ConnectionError value)  connectionError,required TResult Function( BusEvent_ConnectionRemoved value)  connectionRemoved,required TResult Function( BusEvent_ConnectionActiveCountChanged value)  connectionActiveCountChanged,required TResult Function( BusEvent_AutoLockLocked value)  autoLockLocked,required TResult Function( BusEvent_AutoLockUnlocked value)  autoLockUnlocked,required TResult Function( BusEvent_AutoLockTimeoutChanged value)  autoLockTimeoutChanged,required TResult Function( BusEvent_RecorderStarted value)  recorderStarted,required TResult Function( BusEvent_RecorderStopped value)  recorderStopped,required TResult Function( BusEvent_RecorderBytesWritten value)  recorderBytesWritten,required TResult Function( BusEvent_RecorderRotateRequested value)  recorderRotateRequested,required TResult Function( BusEvent_TransferTaskAdded value)  transferTaskAdded,required TResult Function( BusEvent_TransferTaskState value)  transferTaskState,required TResult Function( BusEvent_TransferTaskProgress value)  transferTaskProgress,required TResult Function( BusEvent_TransferTaskError value)  transferTaskError,required TResult Function( BusEvent_PortForwardRegistered value)  portForwardRegistered,required TResult Function( BusEvent_PortForwardStatus value)  portForwardStatus,required TResult Function( BusEvent_PortForwardRemoved value)  portForwardRemoved,required TResult Function( BusEvent_UpdateDownloadProgress value)  updateDownloadProgress,required TResult Function( BusEvent_UpdateVerifyingStarted value)  updateVerifyingStarted,required TResult Function( BusEvent_UpdateDownloadCompleted value)  updateDownloadCompleted,required TResult Function( BusEvent_KnownHostsChanged value)  knownHostsChanged,required TResult Function( BusEvent_SessionsChanged value)  sessionsChanged,required TResult Function( BusEvent_ConfigChanged value)  configChanged,required TResult Function( BusEvent_TierStateChanged value)  tierStateChanged,required TResult Function( BusEvent_KeychainPepperPromptRequest value)  keychainPepperPromptRequest,required TResult Function( BusEvent_CredentialPromptRequest value)  credentialPromptRequest,required TResult Function( BusEvent_BiometricProbePromptRequest value)  biometricProbePromptRequest,required TResult Function( BusEvent_KeychainProbePromptRequest value)  keychainProbePromptRequest,required TResult Function( BusEvent_HardwareVaultProbePromptRequest value)  hardwareVaultProbePromptRequest,required TResult Function( BusEvent_HardwareVaultUnlockPromptRequest value)  hardwareVaultUnlockPromptRequest,required TResult Function( BusEvent_KeychainOpPromptRequest value)  keychainOpPromptRequest,required TResult Function( BusEvent_SecurityCapabilitiesChanged value)  securityCapabilitiesChanged,required TResult Function( BusEvent_KnownHostPromptRequest value)  knownHostPromptRequest,required TResult Function( BusEvent_KnownHostPromptResolved value)  knownHostPromptResolved,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that);case BusEvent_ConnectionProgress():
return connectionProgress(_that);case BusEvent_ConnectionError():
return connectionError(_that);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that);case BusEvent_ConnectionActiveCountChanged():
return connectionActiveCountChanged(_that);case BusEvent_AutoLockLocked():
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked():
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged():
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted():
return recorderStarted(_that);case BusEvent_RecorderStopped():
return recorderStopped(_that);case BusEvent_RecorderBytesWritten():
return recorderBytesWritten(_that);case BusEvent_RecorderRotateRequested():
return recorderRotateRequested(_that);case BusEvent_TransferTaskAdded():
return transferTaskAdded(_that);case BusEvent_TransferTaskState():
return transferTaskState(_that);case BusEvent_TransferTaskProgress():
return transferTaskProgress(_that);case BusEvent_TransferTaskError():
return transferTaskError(_that);case BusEvent_PortForwardRegistered():
return portForwardRegistered(_that);case BusEvent_PortForwardStatus():
return portForwardStatus(_that);case BusEvent_PortForwardRemoved():
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress():
return updateDownloadProgress(_that);case BusEvent_UpdateVerifyingStarted():
return updateVerifyingStarted(_that);case BusEvent_UpdateDownloadCompleted():
return updateDownloadCompleted(_that);case BusEvent_KnownHostsChanged():
return knownHostsChanged(_that);case BusEvent_SessionsChanged():
return sessionsChanged(_that);case BusEvent_ConfigChanged():
return configChanged(_that);case BusEvent_TierStateChanged():
return tierStateChanged(_that);case BusEvent_KeychainPepperPromptRequest():
return keychainPepperPromptRequest(_that);case BusEvent_CredentialPromptRequest():
return credentialPromptRequest(_that);case BusEvent_BiometricProbePromptRequest():
return biometricProbePromptRequest(_that);case BusEvent_KeychainProbePromptRequest():
return keychainProbePromptRequest(_that);case BusEvent_HardwareVaultProbePromptRequest():
return hardwareVaultProbePromptRequest(_that);case BusEvent_HardwareVaultUnlockPromptRequest():
return hardwareVaultUnlockPromptRequest(_that);case BusEvent_KeychainOpPromptRequest():
return keychainOpPromptRequest(_that);case BusEvent_SecurityCapabilitiesChanged():
return securityCapabilitiesChanged(_that);case BusEvent_KnownHostPromptRequest():
return knownHostPromptRequest(_that);case BusEvent_KnownHostPromptResolved():
return knownHostPromptResolved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusEvent_Echoed value)?  echoed,TResult? Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult? Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult? Function( BusEvent_ConnectionError value)?  connectionError,TResult? Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,TResult? Function( BusEvent_ConnectionActiveCountChanged value)?  connectionActiveCountChanged,TResult? Function( BusEvent_AutoLockLocked value)?  autoLockLocked,TResult? Function( BusEvent_AutoLockUnlocked value)?  autoLockUnlocked,TResult? Function( BusEvent_AutoLockTimeoutChanged value)?  autoLockTimeoutChanged,TResult? Function( BusEvent_RecorderStarted value)?  recorderStarted,TResult? Function( BusEvent_RecorderStopped value)?  recorderStopped,TResult? Function( BusEvent_RecorderBytesWritten value)?  recorderBytesWritten,TResult? Function( BusEvent_RecorderRotateRequested value)?  recorderRotateRequested,TResult? Function( BusEvent_TransferTaskAdded value)?  transferTaskAdded,TResult? Function( BusEvent_TransferTaskState value)?  transferTaskState,TResult? Function( BusEvent_TransferTaskProgress value)?  transferTaskProgress,TResult? Function( BusEvent_TransferTaskError value)?  transferTaskError,TResult? Function( BusEvent_PortForwardRegistered value)?  portForwardRegistered,TResult? Function( BusEvent_PortForwardStatus value)?  portForwardStatus,TResult? Function( BusEvent_PortForwardRemoved value)?  portForwardRemoved,TResult? Function( BusEvent_UpdateDownloadProgress value)?  updateDownloadProgress,TResult? Function( BusEvent_UpdateVerifyingStarted value)?  updateVerifyingStarted,TResult? Function( BusEvent_UpdateDownloadCompleted value)?  updateDownloadCompleted,TResult? Function( BusEvent_KnownHostsChanged value)?  knownHostsChanged,TResult? Function( BusEvent_SessionsChanged value)?  sessionsChanged,TResult? Function( BusEvent_ConfigChanged value)?  configChanged,TResult? Function( BusEvent_TierStateChanged value)?  tierStateChanged,TResult? Function( BusEvent_KeychainPepperPromptRequest value)?  keychainPepperPromptRequest,TResult? Function( BusEvent_CredentialPromptRequest value)?  credentialPromptRequest,TResult? Function( BusEvent_BiometricProbePromptRequest value)?  biometricProbePromptRequest,TResult? Function( BusEvent_KeychainProbePromptRequest value)?  keychainProbePromptRequest,TResult? Function( BusEvent_HardwareVaultProbePromptRequest value)?  hardwareVaultProbePromptRequest,TResult? Function( BusEvent_HardwareVaultUnlockPromptRequest value)?  hardwareVaultUnlockPromptRequest,TResult? Function( BusEvent_KeychainOpPromptRequest value)?  keychainOpPromptRequest,TResult? Function( BusEvent_SecurityCapabilitiesChanged value)?  securityCapabilitiesChanged,TResult? Function( BusEvent_KnownHostPromptRequest value)?  knownHostPromptRequest,TResult? Function( BusEvent_KnownHostPromptResolved value)?  knownHostPromptResolved,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case BusEvent_ConnectionActiveCountChanged() when connectionActiveCountChanged != null:
return connectionActiveCountChanged(_that);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked(_that);case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked(_that);case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that);case BusEvent_RecorderRotateRequested() when recorderRotateRequested != null:
return recorderRotateRequested(_that);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that);case BusEvent_UpdateVerifyingStarted() when updateVerifyingStarted != null:
return updateVerifyingStarted(_that);case BusEvent_UpdateDownloadCompleted() when updateDownloadCompleted != null:
return updateDownloadCompleted(_that);case BusEvent_KnownHostsChanged() when knownHostsChanged != null:
return knownHostsChanged(_that);case BusEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged(_that);case BusEvent_ConfigChanged() when configChanged != null:
return configChanged(_that);case BusEvent_TierStateChanged() when tierStateChanged != null:
return tierStateChanged(_that);case BusEvent_KeychainPepperPromptRequest() when keychainPepperPromptRequest != null:
return keychainPepperPromptRequest(_that);case BusEvent_CredentialPromptRequest() when credentialPromptRequest != null:
return credentialPromptRequest(_that);case BusEvent_BiometricProbePromptRequest() when biometricProbePromptRequest != null:
return biometricProbePromptRequest(_that);case BusEvent_KeychainProbePromptRequest() when keychainProbePromptRequest != null:
return keychainProbePromptRequest(_that);case BusEvent_HardwareVaultProbePromptRequest() when hardwareVaultProbePromptRequest != null:
return hardwareVaultProbePromptRequest(_that);case BusEvent_HardwareVaultUnlockPromptRequest() when hardwareVaultUnlockPromptRequest != null:
return hardwareVaultUnlockPromptRequest(_that);case BusEvent_KeychainOpPromptRequest() when keychainOpPromptRequest != null:
return keychainOpPromptRequest(_that);case BusEvent_SecurityCapabilitiesChanged() when securityCapabilitiesChanged != null:
return securityCapabilitiesChanged(_that);case BusEvent_KnownHostPromptRequest() when knownHostPromptRequest != null:
return knownHostPromptRequest(_that);case BusEvent_KnownHostPromptResolved() when knownHostPromptResolved != null:
return knownHostPromptResolved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  echoed,TResult Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult Function( String id,  BusProgressStep step)?  connectionProgress,TResult Function( String id,  String detail)?  connectionError,TResult Function( String id)?  connectionRemoved,TResult Function( PlatformInt64 count)?  connectionActiveCountChanged,TResult Function()?  autoLockLocked,TResult Function()?  autoLockUnlocked,TResult Function( PlatformInt64 minutes)?  autoLockTimeoutChanged,TResult Function( String id,  String path)?  recorderStarted,TResult Function( String id)?  recorderStopped,TResult Function( String id,  BigInt totalBytes)?  recorderBytesWritten,TResult Function( String id,  BigInt bytesWritten)?  recorderRotateRequested,TResult Function( String id)?  transferTaskAdded,TResult Function( String id,  BusTaskState state)?  transferTaskState,TResult Function( String id,  BigInt bytesDone,  BigInt bytesTotal)?  transferTaskProgress,TResult Function( String id,  String detail)?  transferTaskError,TResult Function( String id)?  portForwardRegistered,TResult Function( String id,  BusRuleStatus status,  String? detail)?  portForwardStatus,TResult Function( String id)?  portForwardRemoved,TResult Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)?  updateDownloadProgress,TResult Function( String url)?  updateVerifyingStarted,TResult Function( String url,  String path)?  updateDownloadCompleted,TResult Function()?  knownHostsChanged,TResult Function()?  sessionsChanged,TResult Function( String json)?  configChanged,TResult Function( String stateWireName)?  tierStateChanged,TResult Function( String promptId)?  keychainPepperPromptRequest,TResult Function( String promptId,  String sessionId,  String kindWireName)?  credentialPromptRequest,TResult Function( String promptId)?  biometricProbePromptRequest,TResult Function( String promptId)?  keychainProbePromptRequest,TResult Function( String promptId)?  hardwareVaultProbePromptRequest,TResult Function( String promptId,  String? pin)?  hardwareVaultUnlockPromptRequest,TResult Function( String promptId,  String key,  String opWireName,  String? valueB64)?  keychainOpPromptRequest,TResult Function( String json)?  securityCapabilitiesChanged,TResult Function( String promptId,  String host,  PlatformInt64 port,  String keyType,  String fingerprint,  BusKnownHostPromptKind kind)?  knownHostPromptRequest,TResult Function( String promptId,  bool accepted)?  knownHostPromptResolved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case BusEvent_ConnectionActiveCountChanged() when connectionActiveCountChanged != null:
return connectionActiveCountChanged(_that.count);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked();case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_RecorderRotateRequested() when recorderRotateRequested != null:
return recorderRotateRequested(_that.id,_that.bytesWritten);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);case BusEvent_UpdateVerifyingStarted() when updateVerifyingStarted != null:
return updateVerifyingStarted(_that.url);case BusEvent_UpdateDownloadCompleted() when updateDownloadCompleted != null:
return updateDownloadCompleted(_that.url,_that.path);case BusEvent_KnownHostsChanged() when knownHostsChanged != null:
return knownHostsChanged();case BusEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged();case BusEvent_ConfigChanged() when configChanged != null:
return configChanged(_that.json);case BusEvent_TierStateChanged() when tierStateChanged != null:
return tierStateChanged(_that.stateWireName);case BusEvent_KeychainPepperPromptRequest() when keychainPepperPromptRequest != null:
return keychainPepperPromptRequest(_that.promptId);case BusEvent_CredentialPromptRequest() when credentialPromptRequest != null:
return credentialPromptRequest(_that.promptId,_that.sessionId,_that.kindWireName);case BusEvent_BiometricProbePromptRequest() when biometricProbePromptRequest != null:
return biometricProbePromptRequest(_that.promptId);case BusEvent_KeychainProbePromptRequest() when keychainProbePromptRequest != null:
return keychainProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultProbePromptRequest() when hardwareVaultProbePromptRequest != null:
return hardwareVaultProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultUnlockPromptRequest() when hardwareVaultUnlockPromptRequest != null:
return hardwareVaultUnlockPromptRequest(_that.promptId,_that.pin);case BusEvent_KeychainOpPromptRequest() when keychainOpPromptRequest != null:
return keychainOpPromptRequest(_that.promptId,_that.key,_that.opWireName,_that.valueB64);case BusEvent_SecurityCapabilitiesChanged() when securityCapabilitiesChanged != null:
return securityCapabilitiesChanged(_that.json);case BusEvent_KnownHostPromptRequest() when knownHostPromptRequest != null:
return knownHostPromptRequest(_that.promptId,_that.host,_that.port,_that.keyType,_that.fingerprint,_that.kind);case BusEvent_KnownHostPromptResolved() when knownHostPromptResolved != null:
return knownHostPromptResolved(_that.promptId,_that.accepted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  echoed,required TResult Function( String id,  BusConnectionState state)  connectionStateChanged,required TResult Function( String id,  BusProgressStep step)  connectionProgress,required TResult Function( String id,  String detail)  connectionError,required TResult Function( String id)  connectionRemoved,required TResult Function( PlatformInt64 count)  connectionActiveCountChanged,required TResult Function()  autoLockLocked,required TResult Function()  autoLockUnlocked,required TResult Function( PlatformInt64 minutes)  autoLockTimeoutChanged,required TResult Function( String id,  String path)  recorderStarted,required TResult Function( String id)  recorderStopped,required TResult Function( String id,  BigInt totalBytes)  recorderBytesWritten,required TResult Function( String id,  BigInt bytesWritten)  recorderRotateRequested,required TResult Function( String id)  transferTaskAdded,required TResult Function( String id,  BusTaskState state)  transferTaskState,required TResult Function( String id,  BigInt bytesDone,  BigInt bytesTotal)  transferTaskProgress,required TResult Function( String id,  String detail)  transferTaskError,required TResult Function( String id)  portForwardRegistered,required TResult Function( String id,  BusRuleStatus status,  String? detail)  portForwardStatus,required TResult Function( String id)  portForwardRemoved,required TResult Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)  updateDownloadProgress,required TResult Function( String url)  updateVerifyingStarted,required TResult Function( String url,  String path)  updateDownloadCompleted,required TResult Function()  knownHostsChanged,required TResult Function()  sessionsChanged,required TResult Function( String json)  configChanged,required TResult Function( String stateWireName)  tierStateChanged,required TResult Function( String promptId)  keychainPepperPromptRequest,required TResult Function( String promptId,  String sessionId,  String kindWireName)  credentialPromptRequest,required TResult Function( String promptId)  biometricProbePromptRequest,required TResult Function( String promptId)  keychainProbePromptRequest,required TResult Function( String promptId)  hardwareVaultProbePromptRequest,required TResult Function( String promptId,  String? pin)  hardwareVaultUnlockPromptRequest,required TResult Function( String promptId,  String key,  String opWireName,  String? valueB64)  keychainOpPromptRequest,required TResult Function( String json)  securityCapabilitiesChanged,required TResult Function( String promptId,  String host,  PlatformInt64 port,  String keyType,  String fingerprint,  BusKnownHostPromptKind kind)  knownHostPromptRequest,required TResult Function( String promptId,  bool accepted)  knownHostPromptResolved,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that.payload);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress():
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError():
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that.id);case BusEvent_ConnectionActiveCountChanged():
return connectionActiveCountChanged(_that.count);case BusEvent_AutoLockLocked():
return autoLockLocked();case BusEvent_AutoLockUnlocked():
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged():
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted():
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped():
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten():
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_RecorderRotateRequested():
return recorderRotateRequested(_that.id,_that.bytesWritten);case BusEvent_TransferTaskAdded():
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState():
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress():
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError():
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered():
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus():
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved():
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress():
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);case BusEvent_UpdateVerifyingStarted():
return updateVerifyingStarted(_that.url);case BusEvent_UpdateDownloadCompleted():
return updateDownloadCompleted(_that.url,_that.path);case BusEvent_KnownHostsChanged():
return knownHostsChanged();case BusEvent_SessionsChanged():
return sessionsChanged();case BusEvent_ConfigChanged():
return configChanged(_that.json);case BusEvent_TierStateChanged():
return tierStateChanged(_that.stateWireName);case BusEvent_KeychainPepperPromptRequest():
return keychainPepperPromptRequest(_that.promptId);case BusEvent_CredentialPromptRequest():
return credentialPromptRequest(_that.promptId,_that.sessionId,_that.kindWireName);case BusEvent_BiometricProbePromptRequest():
return biometricProbePromptRequest(_that.promptId);case BusEvent_KeychainProbePromptRequest():
return keychainProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultProbePromptRequest():
return hardwareVaultProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultUnlockPromptRequest():
return hardwareVaultUnlockPromptRequest(_that.promptId,_that.pin);case BusEvent_KeychainOpPromptRequest():
return keychainOpPromptRequest(_that.promptId,_that.key,_that.opWireName,_that.valueB64);case BusEvent_SecurityCapabilitiesChanged():
return securityCapabilitiesChanged(_that.json);case BusEvent_KnownHostPromptRequest():
return knownHostPromptRequest(_that.promptId,_that.host,_that.port,_that.keyType,_that.fingerprint,_that.kind);case BusEvent_KnownHostPromptResolved():
return knownHostPromptResolved(_that.promptId,_that.accepted);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  echoed,TResult? Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult? Function( String id,  BusProgressStep step)?  connectionProgress,TResult? Function( String id,  String detail)?  connectionError,TResult? Function( String id)?  connectionRemoved,TResult? Function( PlatformInt64 count)?  connectionActiveCountChanged,TResult? Function()?  autoLockLocked,TResult? Function()?  autoLockUnlocked,TResult? Function( PlatformInt64 minutes)?  autoLockTimeoutChanged,TResult? Function( String id,  String path)?  recorderStarted,TResult? Function( String id)?  recorderStopped,TResult? Function( String id,  BigInt totalBytes)?  recorderBytesWritten,TResult? Function( String id,  BigInt bytesWritten)?  recorderRotateRequested,TResult? Function( String id)?  transferTaskAdded,TResult? Function( String id,  BusTaskState state)?  transferTaskState,TResult? Function( String id,  BigInt bytesDone,  BigInt bytesTotal)?  transferTaskProgress,TResult? Function( String id,  String detail)?  transferTaskError,TResult? Function( String id)?  portForwardRegistered,TResult? Function( String id,  BusRuleStatus status,  String? detail)?  portForwardStatus,TResult? Function( String id)?  portForwardRemoved,TResult? Function( String url,  BigInt writtenBytes,  BigInt? totalBytes)?  updateDownloadProgress,TResult? Function( String url)?  updateVerifyingStarted,TResult? Function( String url,  String path)?  updateDownloadCompleted,TResult? Function()?  knownHostsChanged,TResult? Function()?  sessionsChanged,TResult? Function( String json)?  configChanged,TResult? Function( String stateWireName)?  tierStateChanged,TResult? Function( String promptId)?  keychainPepperPromptRequest,TResult? Function( String promptId,  String sessionId,  String kindWireName)?  credentialPromptRequest,TResult? Function( String promptId)?  biometricProbePromptRequest,TResult? Function( String promptId)?  keychainProbePromptRequest,TResult? Function( String promptId)?  hardwareVaultProbePromptRequest,TResult? Function( String promptId,  String? pin)?  hardwareVaultUnlockPromptRequest,TResult? Function( String promptId,  String key,  String opWireName,  String? valueB64)?  keychainOpPromptRequest,TResult? Function( String json)?  securityCapabilitiesChanged,TResult? Function( String promptId,  String host,  PlatformInt64 port,  String keyType,  String fingerprint,  BusKnownHostPromptKind kind)?  knownHostPromptRequest,TResult? Function( String promptId,  bool accepted)?  knownHostPromptResolved,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case BusEvent_ConnectionActiveCountChanged() when connectionActiveCountChanged != null:
return connectionActiveCountChanged(_that.count);case BusEvent_AutoLockLocked() when autoLockLocked != null:
return autoLockLocked();case BusEvent_AutoLockUnlocked() when autoLockUnlocked != null:
return autoLockUnlocked();case BusEvent_AutoLockTimeoutChanged() when autoLockTimeoutChanged != null:
return autoLockTimeoutChanged(_that.minutes);case BusEvent_RecorderStarted() when recorderStarted != null:
return recorderStarted(_that.id,_that.path);case BusEvent_RecorderStopped() when recorderStopped != null:
return recorderStopped(_that.id);case BusEvent_RecorderBytesWritten() when recorderBytesWritten != null:
return recorderBytesWritten(_that.id,_that.totalBytes);case BusEvent_RecorderRotateRequested() when recorderRotateRequested != null:
return recorderRotateRequested(_that.id,_that.bytesWritten);case BusEvent_TransferTaskAdded() when transferTaskAdded != null:
return transferTaskAdded(_that.id);case BusEvent_TransferTaskState() when transferTaskState != null:
return transferTaskState(_that.id,_that.state);case BusEvent_TransferTaskProgress() when transferTaskProgress != null:
return transferTaskProgress(_that.id,_that.bytesDone,_that.bytesTotal);case BusEvent_TransferTaskError() when transferTaskError != null:
return transferTaskError(_that.id,_that.detail);case BusEvent_PortForwardRegistered() when portForwardRegistered != null:
return portForwardRegistered(_that.id);case BusEvent_PortForwardStatus() when portForwardStatus != null:
return portForwardStatus(_that.id,_that.status,_that.detail);case BusEvent_PortForwardRemoved() when portForwardRemoved != null:
return portForwardRemoved(_that.id);case BusEvent_UpdateDownloadProgress() when updateDownloadProgress != null:
return updateDownloadProgress(_that.url,_that.writtenBytes,_that.totalBytes);case BusEvent_UpdateVerifyingStarted() when updateVerifyingStarted != null:
return updateVerifyingStarted(_that.url);case BusEvent_UpdateDownloadCompleted() when updateDownloadCompleted != null:
return updateDownloadCompleted(_that.url,_that.path);case BusEvent_KnownHostsChanged() when knownHostsChanged != null:
return knownHostsChanged();case BusEvent_SessionsChanged() when sessionsChanged != null:
return sessionsChanged();case BusEvent_ConfigChanged() when configChanged != null:
return configChanged(_that.json);case BusEvent_TierStateChanged() when tierStateChanged != null:
return tierStateChanged(_that.stateWireName);case BusEvent_KeychainPepperPromptRequest() when keychainPepperPromptRequest != null:
return keychainPepperPromptRequest(_that.promptId);case BusEvent_CredentialPromptRequest() when credentialPromptRequest != null:
return credentialPromptRequest(_that.promptId,_that.sessionId,_that.kindWireName);case BusEvent_BiometricProbePromptRequest() when biometricProbePromptRequest != null:
return biometricProbePromptRequest(_that.promptId);case BusEvent_KeychainProbePromptRequest() when keychainProbePromptRequest != null:
return keychainProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultProbePromptRequest() when hardwareVaultProbePromptRequest != null:
return hardwareVaultProbePromptRequest(_that.promptId);case BusEvent_HardwareVaultUnlockPromptRequest() when hardwareVaultUnlockPromptRequest != null:
return hardwareVaultUnlockPromptRequest(_that.promptId,_that.pin);case BusEvent_KeychainOpPromptRequest() when keychainOpPromptRequest != null:
return keychainOpPromptRequest(_that.promptId,_that.key,_that.opWireName,_that.valueB64);case BusEvent_SecurityCapabilitiesChanged() when securityCapabilitiesChanged != null:
return securityCapabilitiesChanged(_that.json);case BusEvent_KnownHostPromptRequest() when knownHostPromptRequest != null:
return knownHostPromptRequest(_that.promptId,_that.host,_that.port,_that.keyType,_that.fingerprint,_that.kind);case BusEvent_KnownHostPromptResolved() when knownHostPromptResolved != null:
return knownHostPromptResolved(_that.promptId,_that.accepted);case _:
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


class BusEvent_ConnectionActiveCountChanged extends BusEvent {
  const BusEvent_ConnectionActiveCountChanged({required this.count}): super._();
  

 final  PlatformInt64 count;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConnectionActiveCountChangedCopyWith<BusEvent_ConnectionActiveCountChanged> get copyWith => _$BusEvent_ConnectionActiveCountChangedCopyWithImpl<BusEvent_ConnectionActiveCountChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConnectionActiveCountChanged&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode => Object.hash(runtimeType,count);

@override
String toString() {
  return 'BusEvent.connectionActiveCountChanged(count: $count)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConnectionActiveCountChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConnectionActiveCountChangedCopyWith(BusEvent_ConnectionActiveCountChanged value, $Res Function(BusEvent_ConnectionActiveCountChanged) _then) = _$BusEvent_ConnectionActiveCountChangedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 count
});




}
/// @nodoc
class _$BusEvent_ConnectionActiveCountChangedCopyWithImpl<$Res>
    implements $BusEvent_ConnectionActiveCountChangedCopyWith<$Res> {
  _$BusEvent_ConnectionActiveCountChangedCopyWithImpl(this._self, this._then);

  final BusEvent_ConnectionActiveCountChanged _self;
  final $Res Function(BusEvent_ConnectionActiveCountChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? count = null,}) {
  return _then(BusEvent_ConnectionActiveCountChanged(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
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


class BusEvent_RecorderRotateRequested extends BusEvent {
  const BusEvent_RecorderRotateRequested({required this.id, required this.bytesWritten}): super._();
  

 final  String id;
 final  BigInt bytesWritten;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_RecorderRotateRequestedCopyWith<BusEvent_RecorderRotateRequested> get copyWith => _$BusEvent_RecorderRotateRequestedCopyWithImpl<BusEvent_RecorderRotateRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_RecorderRotateRequested&&(identical(other.id, id) || other.id == id)&&(identical(other.bytesWritten, bytesWritten) || other.bytesWritten == bytesWritten));
}


@override
int get hashCode => Object.hash(runtimeType,id,bytesWritten);

@override
String toString() {
  return 'BusEvent.recorderRotateRequested(id: $id, bytesWritten: $bytesWritten)';
}


}

/// @nodoc
abstract mixin class $BusEvent_RecorderRotateRequestedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_RecorderRotateRequestedCopyWith(BusEvent_RecorderRotateRequested value, $Res Function(BusEvent_RecorderRotateRequested) _then) = _$BusEvent_RecorderRotateRequestedCopyWithImpl;
@useResult
$Res call({
 String id, BigInt bytesWritten
});




}
/// @nodoc
class _$BusEvent_RecorderRotateRequestedCopyWithImpl<$Res>
    implements $BusEvent_RecorderRotateRequestedCopyWith<$Res> {
  _$BusEvent_RecorderRotateRequestedCopyWithImpl(this._self, this._then);

  final BusEvent_RecorderRotateRequested _self;
  final $Res Function(BusEvent_RecorderRotateRequested) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bytesWritten = null,}) {
  return _then(BusEvent_RecorderRotateRequested(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bytesWritten: null == bytesWritten ? _self.bytesWritten : bytesWritten // ignore: cast_nullable_to_non_nullable
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

/// @nodoc


class BusEvent_UpdateVerifyingStarted extends BusEvent {
  const BusEvent_UpdateVerifyingStarted({required this.url}): super._();
  

 final  String url;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_UpdateVerifyingStartedCopyWith<BusEvent_UpdateVerifyingStarted> get copyWith => _$BusEvent_UpdateVerifyingStartedCopyWithImpl<BusEvent_UpdateVerifyingStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_UpdateVerifyingStarted&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode => Object.hash(runtimeType,url);

@override
String toString() {
  return 'BusEvent.updateVerifyingStarted(url: $url)';
}


}

/// @nodoc
abstract mixin class $BusEvent_UpdateVerifyingStartedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_UpdateVerifyingStartedCopyWith(BusEvent_UpdateVerifyingStarted value, $Res Function(BusEvent_UpdateVerifyingStarted) _then) = _$BusEvent_UpdateVerifyingStartedCopyWithImpl;
@useResult
$Res call({
 String url
});




}
/// @nodoc
class _$BusEvent_UpdateVerifyingStartedCopyWithImpl<$Res>
    implements $BusEvent_UpdateVerifyingStartedCopyWith<$Res> {
  _$BusEvent_UpdateVerifyingStartedCopyWithImpl(this._self, this._then);

  final BusEvent_UpdateVerifyingStarted _self;
  final $Res Function(BusEvent_UpdateVerifyingStarted) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(BusEvent_UpdateVerifyingStarted(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_UpdateDownloadCompleted extends BusEvent {
  const BusEvent_UpdateDownloadCompleted({required this.url, required this.path}): super._();
  

 final  String url;
 final  String path;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_UpdateDownloadCompletedCopyWith<BusEvent_UpdateDownloadCompleted> get copyWith => _$BusEvent_UpdateDownloadCompletedCopyWithImpl<BusEvent_UpdateDownloadCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_UpdateDownloadCompleted&&(identical(other.url, url) || other.url == url)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,url,path);

@override
String toString() {
  return 'BusEvent.updateDownloadCompleted(url: $url, path: $path)';
}


}

/// @nodoc
abstract mixin class $BusEvent_UpdateDownloadCompletedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_UpdateDownloadCompletedCopyWith(BusEvent_UpdateDownloadCompleted value, $Res Function(BusEvent_UpdateDownloadCompleted) _then) = _$BusEvent_UpdateDownloadCompletedCopyWithImpl;
@useResult
$Res call({
 String url, String path
});




}
/// @nodoc
class _$BusEvent_UpdateDownloadCompletedCopyWithImpl<$Res>
    implements $BusEvent_UpdateDownloadCompletedCopyWith<$Res> {
  _$BusEvent_UpdateDownloadCompletedCopyWithImpl(this._self, this._then);

  final BusEvent_UpdateDownloadCompleted _self;
  final $Res Function(BusEvent_UpdateDownloadCompleted) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? path = null,}) {
  return _then(BusEvent_UpdateDownloadCompleted(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_KnownHostsChanged extends BusEvent {
  const BusEvent_KnownHostsChanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KnownHostsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusEvent.knownHostsChanged()';
}


}




/// @nodoc


class BusEvent_SessionsChanged extends BusEvent {
  const BusEvent_SessionsChanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_SessionsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BusEvent.sessionsChanged()';
}


}




/// @nodoc


class BusEvent_ConfigChanged extends BusEvent {
  const BusEvent_ConfigChanged({required this.json}): super._();
  

 final  String json;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_ConfigChangedCopyWith<BusEvent_ConfigChanged> get copyWith => _$BusEvent_ConfigChangedCopyWithImpl<BusEvent_ConfigChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_ConfigChanged&&(identical(other.json, json) || other.json == json));
}


@override
int get hashCode => Object.hash(runtimeType,json);

@override
String toString() {
  return 'BusEvent.configChanged(json: $json)';
}


}

/// @nodoc
abstract mixin class $BusEvent_ConfigChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_ConfigChangedCopyWith(BusEvent_ConfigChanged value, $Res Function(BusEvent_ConfigChanged) _then) = _$BusEvent_ConfigChangedCopyWithImpl;
@useResult
$Res call({
 String json
});




}
/// @nodoc
class _$BusEvent_ConfigChangedCopyWithImpl<$Res>
    implements $BusEvent_ConfigChangedCopyWith<$Res> {
  _$BusEvent_ConfigChangedCopyWithImpl(this._self, this._then);

  final BusEvent_ConfigChanged _self;
  final $Res Function(BusEvent_ConfigChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(BusEvent_ConfigChanged(
json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_TierStateChanged extends BusEvent {
  const BusEvent_TierStateChanged({required this.stateWireName}): super._();
  

 final  String stateWireName;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_TierStateChangedCopyWith<BusEvent_TierStateChanged> get copyWith => _$BusEvent_TierStateChangedCopyWithImpl<BusEvent_TierStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_TierStateChanged&&(identical(other.stateWireName, stateWireName) || other.stateWireName == stateWireName));
}


@override
int get hashCode => Object.hash(runtimeType,stateWireName);

@override
String toString() {
  return 'BusEvent.tierStateChanged(stateWireName: $stateWireName)';
}


}

/// @nodoc
abstract mixin class $BusEvent_TierStateChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_TierStateChangedCopyWith(BusEvent_TierStateChanged value, $Res Function(BusEvent_TierStateChanged) _then) = _$BusEvent_TierStateChangedCopyWithImpl;
@useResult
$Res call({
 String stateWireName
});




}
/// @nodoc
class _$BusEvent_TierStateChangedCopyWithImpl<$Res>
    implements $BusEvent_TierStateChangedCopyWith<$Res> {
  _$BusEvent_TierStateChangedCopyWithImpl(this._self, this._then);

  final BusEvent_TierStateChanged _self;
  final $Res Function(BusEvent_TierStateChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stateWireName = null,}) {
  return _then(BusEvent_TierStateChanged(
stateWireName: null == stateWireName ? _self.stateWireName : stateWireName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_KeychainPepperPromptRequest extends BusEvent {
  const BusEvent_KeychainPepperPromptRequest({required this.promptId}): super._();
  

 final  String promptId;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_KeychainPepperPromptRequestCopyWith<BusEvent_KeychainPepperPromptRequest> get copyWith => _$BusEvent_KeychainPepperPromptRequestCopyWithImpl<BusEvent_KeychainPepperPromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KeychainPepperPromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId));
}


@override
int get hashCode => Object.hash(runtimeType,promptId);

@override
String toString() {
  return 'BusEvent.keychainPepperPromptRequest(promptId: $promptId)';
}


}

/// @nodoc
abstract mixin class $BusEvent_KeychainPepperPromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_KeychainPepperPromptRequestCopyWith(BusEvent_KeychainPepperPromptRequest value, $Res Function(BusEvent_KeychainPepperPromptRequest) _then) = _$BusEvent_KeychainPepperPromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId
});




}
/// @nodoc
class _$BusEvent_KeychainPepperPromptRequestCopyWithImpl<$Res>
    implements $BusEvent_KeychainPepperPromptRequestCopyWith<$Res> {
  _$BusEvent_KeychainPepperPromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_KeychainPepperPromptRequest _self;
  final $Res Function(BusEvent_KeychainPepperPromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,}) {
  return _then(BusEvent_KeychainPepperPromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_CredentialPromptRequest extends BusEvent {
  const BusEvent_CredentialPromptRequest({required this.promptId, required this.sessionId, required this.kindWireName}): super._();
  

 final  String promptId;
 final  String sessionId;
 final  String kindWireName;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_CredentialPromptRequestCopyWith<BusEvent_CredentialPromptRequest> get copyWith => _$BusEvent_CredentialPromptRequestCopyWithImpl<BusEvent_CredentialPromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_CredentialPromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.kindWireName, kindWireName) || other.kindWireName == kindWireName));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,sessionId,kindWireName);

@override
String toString() {
  return 'BusEvent.credentialPromptRequest(promptId: $promptId, sessionId: $sessionId, kindWireName: $kindWireName)';
}


}

/// @nodoc
abstract mixin class $BusEvent_CredentialPromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_CredentialPromptRequestCopyWith(BusEvent_CredentialPromptRequest value, $Res Function(BusEvent_CredentialPromptRequest) _then) = _$BusEvent_CredentialPromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId, String sessionId, String kindWireName
});




}
/// @nodoc
class _$BusEvent_CredentialPromptRequestCopyWithImpl<$Res>
    implements $BusEvent_CredentialPromptRequestCopyWith<$Res> {
  _$BusEvent_CredentialPromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_CredentialPromptRequest _self;
  final $Res Function(BusEvent_CredentialPromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? sessionId = null,Object? kindWireName = null,}) {
  return _then(BusEvent_CredentialPromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,kindWireName: null == kindWireName ? _self.kindWireName : kindWireName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_BiometricProbePromptRequest extends BusEvent {
  const BusEvent_BiometricProbePromptRequest({required this.promptId}): super._();
  

 final  String promptId;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_BiometricProbePromptRequestCopyWith<BusEvent_BiometricProbePromptRequest> get copyWith => _$BusEvent_BiometricProbePromptRequestCopyWithImpl<BusEvent_BiometricProbePromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_BiometricProbePromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId));
}


@override
int get hashCode => Object.hash(runtimeType,promptId);

@override
String toString() {
  return 'BusEvent.biometricProbePromptRequest(promptId: $promptId)';
}


}

/// @nodoc
abstract mixin class $BusEvent_BiometricProbePromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_BiometricProbePromptRequestCopyWith(BusEvent_BiometricProbePromptRequest value, $Res Function(BusEvent_BiometricProbePromptRequest) _then) = _$BusEvent_BiometricProbePromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId
});




}
/// @nodoc
class _$BusEvent_BiometricProbePromptRequestCopyWithImpl<$Res>
    implements $BusEvent_BiometricProbePromptRequestCopyWith<$Res> {
  _$BusEvent_BiometricProbePromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_BiometricProbePromptRequest _self;
  final $Res Function(BusEvent_BiometricProbePromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,}) {
  return _then(BusEvent_BiometricProbePromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_KeychainProbePromptRequest extends BusEvent {
  const BusEvent_KeychainProbePromptRequest({required this.promptId}): super._();
  

 final  String promptId;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_KeychainProbePromptRequestCopyWith<BusEvent_KeychainProbePromptRequest> get copyWith => _$BusEvent_KeychainProbePromptRequestCopyWithImpl<BusEvent_KeychainProbePromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KeychainProbePromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId));
}


@override
int get hashCode => Object.hash(runtimeType,promptId);

@override
String toString() {
  return 'BusEvent.keychainProbePromptRequest(promptId: $promptId)';
}


}

/// @nodoc
abstract mixin class $BusEvent_KeychainProbePromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_KeychainProbePromptRequestCopyWith(BusEvent_KeychainProbePromptRequest value, $Res Function(BusEvent_KeychainProbePromptRequest) _then) = _$BusEvent_KeychainProbePromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId
});




}
/// @nodoc
class _$BusEvent_KeychainProbePromptRequestCopyWithImpl<$Res>
    implements $BusEvent_KeychainProbePromptRequestCopyWith<$Res> {
  _$BusEvent_KeychainProbePromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_KeychainProbePromptRequest _self;
  final $Res Function(BusEvent_KeychainProbePromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,}) {
  return _then(BusEvent_KeychainProbePromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_HardwareVaultProbePromptRequest extends BusEvent {
  const BusEvent_HardwareVaultProbePromptRequest({required this.promptId}): super._();
  

 final  String promptId;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_HardwareVaultProbePromptRequestCopyWith<BusEvent_HardwareVaultProbePromptRequest> get copyWith => _$BusEvent_HardwareVaultProbePromptRequestCopyWithImpl<BusEvent_HardwareVaultProbePromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_HardwareVaultProbePromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId));
}


@override
int get hashCode => Object.hash(runtimeType,promptId);

@override
String toString() {
  return 'BusEvent.hardwareVaultProbePromptRequest(promptId: $promptId)';
}


}

/// @nodoc
abstract mixin class $BusEvent_HardwareVaultProbePromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_HardwareVaultProbePromptRequestCopyWith(BusEvent_HardwareVaultProbePromptRequest value, $Res Function(BusEvent_HardwareVaultProbePromptRequest) _then) = _$BusEvent_HardwareVaultProbePromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId
});




}
/// @nodoc
class _$BusEvent_HardwareVaultProbePromptRequestCopyWithImpl<$Res>
    implements $BusEvent_HardwareVaultProbePromptRequestCopyWith<$Res> {
  _$BusEvent_HardwareVaultProbePromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_HardwareVaultProbePromptRequest _self;
  final $Res Function(BusEvent_HardwareVaultProbePromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,}) {
  return _then(BusEvent_HardwareVaultProbePromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_HardwareVaultUnlockPromptRequest extends BusEvent {
  const BusEvent_HardwareVaultUnlockPromptRequest({required this.promptId, this.pin}): super._();
  

 final  String promptId;
 final  String? pin;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_HardwareVaultUnlockPromptRequestCopyWith<BusEvent_HardwareVaultUnlockPromptRequest> get copyWith => _$BusEvent_HardwareVaultUnlockPromptRequestCopyWithImpl<BusEvent_HardwareVaultUnlockPromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_HardwareVaultUnlockPromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.pin, pin) || other.pin == pin));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,pin);

@override
String toString() {
  return 'BusEvent.hardwareVaultUnlockPromptRequest(promptId: $promptId, pin: $pin)';
}


}

/// @nodoc
abstract mixin class $BusEvent_HardwareVaultUnlockPromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_HardwareVaultUnlockPromptRequestCopyWith(BusEvent_HardwareVaultUnlockPromptRequest value, $Res Function(BusEvent_HardwareVaultUnlockPromptRequest) _then) = _$BusEvent_HardwareVaultUnlockPromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId, String? pin
});




}
/// @nodoc
class _$BusEvent_HardwareVaultUnlockPromptRequestCopyWithImpl<$Res>
    implements $BusEvent_HardwareVaultUnlockPromptRequestCopyWith<$Res> {
  _$BusEvent_HardwareVaultUnlockPromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_HardwareVaultUnlockPromptRequest _self;
  final $Res Function(BusEvent_HardwareVaultUnlockPromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? pin = freezed,}) {
  return _then(BusEvent_HardwareVaultUnlockPromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,pin: freezed == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BusEvent_KeychainOpPromptRequest extends BusEvent {
  const BusEvent_KeychainOpPromptRequest({required this.promptId, required this.key, required this.opWireName, this.valueB64}): super._();
  

 final  String promptId;
 final  String key;
 final  String opWireName;
 final  String? valueB64;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_KeychainOpPromptRequestCopyWith<BusEvent_KeychainOpPromptRequest> get copyWith => _$BusEvent_KeychainOpPromptRequestCopyWithImpl<BusEvent_KeychainOpPromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KeychainOpPromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.key, key) || other.key == key)&&(identical(other.opWireName, opWireName) || other.opWireName == opWireName)&&(identical(other.valueB64, valueB64) || other.valueB64 == valueB64));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,key,opWireName,valueB64);

@override
String toString() {
  return 'BusEvent.keychainOpPromptRequest(promptId: $promptId, key: $key, opWireName: $opWireName, valueB64: $valueB64)';
}


}

/// @nodoc
abstract mixin class $BusEvent_KeychainOpPromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_KeychainOpPromptRequestCopyWith(BusEvent_KeychainOpPromptRequest value, $Res Function(BusEvent_KeychainOpPromptRequest) _then) = _$BusEvent_KeychainOpPromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId, String key, String opWireName, String? valueB64
});




}
/// @nodoc
class _$BusEvent_KeychainOpPromptRequestCopyWithImpl<$Res>
    implements $BusEvent_KeychainOpPromptRequestCopyWith<$Res> {
  _$BusEvent_KeychainOpPromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_KeychainOpPromptRequest _self;
  final $Res Function(BusEvent_KeychainOpPromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? key = null,Object? opWireName = null,Object? valueB64 = freezed,}) {
  return _then(BusEvent_KeychainOpPromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,opWireName: null == opWireName ? _self.opWireName : opWireName // ignore: cast_nullable_to_non_nullable
as String,valueB64: freezed == valueB64 ? _self.valueB64 : valueB64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BusEvent_SecurityCapabilitiesChanged extends BusEvent {
  const BusEvent_SecurityCapabilitiesChanged({required this.json}): super._();
  

 final  String json;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_SecurityCapabilitiesChangedCopyWith<BusEvent_SecurityCapabilitiesChanged> get copyWith => _$BusEvent_SecurityCapabilitiesChangedCopyWithImpl<BusEvent_SecurityCapabilitiesChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_SecurityCapabilitiesChanged&&(identical(other.json, json) || other.json == json));
}


@override
int get hashCode => Object.hash(runtimeType,json);

@override
String toString() {
  return 'BusEvent.securityCapabilitiesChanged(json: $json)';
}


}

/// @nodoc
abstract mixin class $BusEvent_SecurityCapabilitiesChangedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_SecurityCapabilitiesChangedCopyWith(BusEvent_SecurityCapabilitiesChanged value, $Res Function(BusEvent_SecurityCapabilitiesChanged) _then) = _$BusEvent_SecurityCapabilitiesChangedCopyWithImpl;
@useResult
$Res call({
 String json
});




}
/// @nodoc
class _$BusEvent_SecurityCapabilitiesChangedCopyWithImpl<$Res>
    implements $BusEvent_SecurityCapabilitiesChangedCopyWith<$Res> {
  _$BusEvent_SecurityCapabilitiesChangedCopyWithImpl(this._self, this._then);

  final BusEvent_SecurityCapabilitiesChanged _self;
  final $Res Function(BusEvent_SecurityCapabilitiesChanged) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(BusEvent_SecurityCapabilitiesChanged(
json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BusEvent_KnownHostPromptRequest extends BusEvent {
  const BusEvent_KnownHostPromptRequest({required this.promptId, required this.host, required this.port, required this.keyType, required this.fingerprint, required this.kind}): super._();
  

 final  String promptId;
 final  String host;
 final  PlatformInt64 port;
 final  String keyType;
 final  String fingerprint;
 final  BusKnownHostPromptKind kind;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_KnownHostPromptRequestCopyWith<BusEvent_KnownHostPromptRequest> get copyWith => _$BusEvent_KnownHostPromptRequestCopyWithImpl<BusEvent_KnownHostPromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KnownHostPromptRequest&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.keyType, keyType) || other.keyType == keyType)&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,host,port,keyType,fingerprint,kind);

@override
String toString() {
  return 'BusEvent.knownHostPromptRequest(promptId: $promptId, host: $host, port: $port, keyType: $keyType, fingerprint: $fingerprint, kind: $kind)';
}


}

/// @nodoc
abstract mixin class $BusEvent_KnownHostPromptRequestCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_KnownHostPromptRequestCopyWith(BusEvent_KnownHostPromptRequest value, $Res Function(BusEvent_KnownHostPromptRequest) _then) = _$BusEvent_KnownHostPromptRequestCopyWithImpl;
@useResult
$Res call({
 String promptId, String host, PlatformInt64 port, String keyType, String fingerprint, BusKnownHostPromptKind kind
});




}
/// @nodoc
class _$BusEvent_KnownHostPromptRequestCopyWithImpl<$Res>
    implements $BusEvent_KnownHostPromptRequestCopyWith<$Res> {
  _$BusEvent_KnownHostPromptRequestCopyWithImpl(this._self, this._then);

  final BusEvent_KnownHostPromptRequest _self;
  final $Res Function(BusEvent_KnownHostPromptRequest) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? host = null,Object? port = null,Object? keyType = null,Object? fingerprint = null,Object? kind = null,}) {
  return _then(BusEvent_KnownHostPromptRequest(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PlatformInt64,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BusKnownHostPromptKind,
  ));
}


}

/// @nodoc


class BusEvent_KnownHostPromptResolved extends BusEvent {
  const BusEvent_KnownHostPromptResolved({required this.promptId, required this.accepted}): super._();
  

 final  String promptId;
 final  bool accepted;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEvent_KnownHostPromptResolvedCopyWith<BusEvent_KnownHostPromptResolved> get copyWith => _$BusEvent_KnownHostPromptResolvedCopyWithImpl<BusEvent_KnownHostPromptResolved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent_KnownHostPromptResolved&&(identical(other.promptId, promptId) || other.promptId == promptId)&&(identical(other.accepted, accepted) || other.accepted == accepted));
}


@override
int get hashCode => Object.hash(runtimeType,promptId,accepted);

@override
String toString() {
  return 'BusEvent.knownHostPromptResolved(promptId: $promptId, accepted: $accepted)';
}


}

/// @nodoc
abstract mixin class $BusEvent_KnownHostPromptResolvedCopyWith<$Res> implements $BusEventCopyWith<$Res> {
  factory $BusEvent_KnownHostPromptResolvedCopyWith(BusEvent_KnownHostPromptResolved value, $Res Function(BusEvent_KnownHostPromptResolved) _then) = _$BusEvent_KnownHostPromptResolvedCopyWithImpl;
@useResult
$Res call({
 String promptId, bool accepted
});




}
/// @nodoc
class _$BusEvent_KnownHostPromptResolvedCopyWithImpl<$Res>
    implements $BusEvent_KnownHostPromptResolvedCopyWith<$Res> {
  _$BusEvent_KnownHostPromptResolvedCopyWithImpl(this._self, this._then);

  final BusEvent_KnownHostPromptResolved _self;
  final $Res Function(BusEvent_KnownHostPromptResolved) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? promptId = null,Object? accepted = null,}) {
  return _then(BusEvent_KnownHostPromptResolved(
promptId: null == promptId ? _self.promptId : promptId // ignore: cast_nullable_to_non_nullable
as String,accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
