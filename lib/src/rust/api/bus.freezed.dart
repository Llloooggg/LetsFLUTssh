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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusCommand_NoopEcho value)?  noopEcho,TResult Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusCommand_NoopEcho value)  noopEcho,required TResult Function( BusCommand_ConnectionDisconnect value)  connectionDisconnect,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that);case BusCommand_ConnectionDisconnect():
return connectionDisconnect(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusCommand_NoopEcho value)?  noopEcho,TResult? Function( BusCommand_ConnectionDisconnect value)?  connectionDisconnect,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  noopEcho,TResult Function( String id)?  connectionDisconnect,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  noopEcho,required TResult Function( String id)  connectionDisconnect,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect():
return connectionDisconnect(_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  noopEcho,TResult? Function( String id)?  connectionDisconnect,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case BusCommand_ConnectionDisconnect() when connectionDisconnect != null:
return connectionDisconnect(_that.id);case _:
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusEvent_Echoed value)?  echoed,TResult Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult Function( BusEvent_ConnectionError value)?  connectionError,TResult Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusEvent_Echoed value)  echoed,required TResult Function( BusEvent_ConnectionStateChanged value)  connectionStateChanged,required TResult Function( BusEvent_ConnectionProgress value)  connectionProgress,required TResult Function( BusEvent_ConnectionError value)  connectionError,required TResult Function( BusEvent_ConnectionRemoved value)  connectionRemoved,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that);case BusEvent_ConnectionProgress():
return connectionProgress(_that);case BusEvent_ConnectionError():
return connectionError(_that);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusEvent_Echoed value)?  echoed,TResult? Function( BusEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult? Function( BusEvent_ConnectionProgress value)?  connectionProgress,TResult? Function( BusEvent_ConnectionError value)?  connectionError,TResult? Function( BusEvent_ConnectionRemoved value)?  connectionRemoved,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  echoed,TResult Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult Function( String id,  BusProgressStep step)?  connectionProgress,TResult Function( String id,  String detail)?  connectionError,TResult Function( String id)?  connectionRemoved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  echoed,required TResult Function( String id,  BusConnectionState state)  connectionStateChanged,required TResult Function( String id,  BusProgressStep step)  connectionProgress,required TResult Function( String id,  String detail)  connectionError,required TResult Function( String id)  connectionRemoved,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that.payload);case BusEvent_ConnectionStateChanged():
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress():
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError():
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved():
return connectionRemoved(_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  echoed,TResult? Function( String id,  BusConnectionState state)?  connectionStateChanged,TResult? Function( String id,  BusProgressStep step)?  connectionProgress,TResult? Function( String id,  String detail)?  connectionError,TResult? Function( String id)?  connectionRemoved,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case BusEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.id,_that.state);case BusEvent_ConnectionProgress() when connectionProgress != null:
return connectionProgress(_that.id,_that.step);case BusEvent_ConnectionError() when connectionError != null:
return connectionError(_that.id,_that.detail);case BusEvent_ConnectionRemoved() when connectionRemoved != null:
return connectionRemoved(_that.id);case _:
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

// dart format on
