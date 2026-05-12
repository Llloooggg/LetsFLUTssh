// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_compose.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbPreparedAuthRef {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbPreparedAuthRef()';
}


}

/// @nodoc
class $DbPreparedAuthRefCopyWith<$Res>  {
$DbPreparedAuthRefCopyWith(DbPreparedAuthRef _, $Res Function(DbPreparedAuthRef) __);
}


/// Adds pattern-matching-related methods to [DbPreparedAuthRef].
extension DbPreparedAuthRefPatterns on DbPreparedAuthRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbPreparedAuthRef_Password value)?  password,TResult Function( DbPreparedAuthRef_Pubkey value)?  pubkey,TResult Function( DbPreparedAuthRef_PubkeyCert value)?  pubkeyCert,TResult Function( DbPreparedAuthRef_PubkeySk value)?  pubkeySk,TResult Function( DbPreparedAuthRef_PubkeyPkcs11 value)?  pubkeyPkcs11,TResult Function( DbPreparedAuthRef_PubkeyEnclave value)?  pubkeyEnclave,TResult Function( DbPreparedAuthRef_PubkeyHello value)?  pubkeyHello,TResult Function( DbPreparedAuthRef_PubkeyTpm value)?  pubkeyTpm,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case DbPreparedAuthRef_PubkeySk() when pubkeySk != null:
return pubkeySk(_that);case DbPreparedAuthRef_PubkeyPkcs11() when pubkeyPkcs11 != null:
return pubkeyPkcs11(_that);case DbPreparedAuthRef_PubkeyEnclave() when pubkeyEnclave != null:
return pubkeyEnclave(_that);case DbPreparedAuthRef_PubkeyHello() when pubkeyHello != null:
return pubkeyHello(_that);case DbPreparedAuthRef_PubkeyTpm() when pubkeyTpm != null:
return pubkeyTpm(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbPreparedAuthRef_Password value)  password,required TResult Function( DbPreparedAuthRef_Pubkey value)  pubkey,required TResult Function( DbPreparedAuthRef_PubkeyCert value)  pubkeyCert,required TResult Function( DbPreparedAuthRef_PubkeySk value)  pubkeySk,required TResult Function( DbPreparedAuthRef_PubkeyPkcs11 value)  pubkeyPkcs11,required TResult Function( DbPreparedAuthRef_PubkeyEnclave value)  pubkeyEnclave,required TResult Function( DbPreparedAuthRef_PubkeyHello value)  pubkeyHello,required TResult Function( DbPreparedAuthRef_PubkeyTpm value)  pubkeyTpm,}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password():
return password(_that);case DbPreparedAuthRef_Pubkey():
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert():
return pubkeyCert(_that);case DbPreparedAuthRef_PubkeySk():
return pubkeySk(_that);case DbPreparedAuthRef_PubkeyPkcs11():
return pubkeyPkcs11(_that);case DbPreparedAuthRef_PubkeyEnclave():
return pubkeyEnclave(_that);case DbPreparedAuthRef_PubkeyHello():
return pubkeyHello(_that);case DbPreparedAuthRef_PubkeyTpm():
return pubkeyTpm(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbPreparedAuthRef_Password value)?  password,TResult? Function( DbPreparedAuthRef_Pubkey value)?  pubkey,TResult? Function( DbPreparedAuthRef_PubkeyCert value)?  pubkeyCert,TResult? Function( DbPreparedAuthRef_PubkeySk value)?  pubkeySk,TResult? Function( DbPreparedAuthRef_PubkeyPkcs11 value)?  pubkeyPkcs11,TResult? Function( DbPreparedAuthRef_PubkeyEnclave value)?  pubkeyEnclave,TResult? Function( DbPreparedAuthRef_PubkeyHello value)?  pubkeyHello,TResult? Function( DbPreparedAuthRef_PubkeyTpm value)?  pubkeyTpm,}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case DbPreparedAuthRef_PubkeySk() when pubkeySk != null:
return pubkeySk(_that);case DbPreparedAuthRef_PubkeyPkcs11() when pubkeyPkcs11 != null:
return pubkeyPkcs11(_that);case DbPreparedAuthRef_PubkeyEnclave() when pubkeyEnclave != null:
return pubkeyEnclave(_that);case DbPreparedAuthRef_PubkeyHello() when pubkeyHello != null:
return pubkeyHello(_that);case DbPreparedAuthRef_PubkeyTpm() when pubkeyTpm != null:
return pubkeyTpm(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String secretId)?  password,TResult Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,TResult Function( String publicOpenssh,  Uint8List credentialId,  String application,  bool hasUserVerification,  String? pinSecretId)?  pubkeySk,TResult Function( String publicOpenssh,  String modulePath,  String tokenSerial,  Uint8List ckaId,  String keyType,  String? pinSecretId)?  pubkeyPkcs11,TResult Function( String publicOpenssh,  Uint8List applicationTag)?  pubkeyEnclave,TResult Function( String publicOpenssh,  String credentialName,  String keyType)?  pubkeyHello,TResult Function( String publicOpenssh,  String provider,  Uint8List? blob,  String? cngKeyName,  String keyType,  String? pinSecretId)?  pubkeyTpm,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that.secretId);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeySk() when pubkeySk != null:
return pubkeySk(_that.publicOpenssh,_that.credentialId,_that.application,_that.hasUserVerification,_that.pinSecretId);case DbPreparedAuthRef_PubkeyPkcs11() when pubkeyPkcs11 != null:
return pubkeyPkcs11(_that.publicOpenssh,_that.modulePath,_that.tokenSerial,_that.ckaId,_that.keyType,_that.pinSecretId);case DbPreparedAuthRef_PubkeyEnclave() when pubkeyEnclave != null:
return pubkeyEnclave(_that.publicOpenssh,_that.applicationTag);case DbPreparedAuthRef_PubkeyHello() when pubkeyHello != null:
return pubkeyHello(_that.publicOpenssh,_that.credentialName,_that.keyType);case DbPreparedAuthRef_PubkeyTpm() when pubkeyTpm != null:
return pubkeyTpm(_that.publicOpenssh,_that.provider,_that.blob,_that.cngKeyName,_that.keyType,_that.pinSecretId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String secretId)  password,required TResult Function( String keySecretId,  String? passphraseSecretId)  pubkey,required TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)  pubkeyCert,required TResult Function( String publicOpenssh,  Uint8List credentialId,  String application,  bool hasUserVerification,  String? pinSecretId)  pubkeySk,required TResult Function( String publicOpenssh,  String modulePath,  String tokenSerial,  Uint8List ckaId,  String keyType,  String? pinSecretId)  pubkeyPkcs11,required TResult Function( String publicOpenssh,  Uint8List applicationTag)  pubkeyEnclave,required TResult Function( String publicOpenssh,  String credentialName,  String keyType)  pubkeyHello,required TResult Function( String publicOpenssh,  String provider,  Uint8List? blob,  String? cngKeyName,  String keyType,  String? pinSecretId)  pubkeyTpm,}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password():
return password(_that.secretId);case DbPreparedAuthRef_Pubkey():
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert():
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeySk():
return pubkeySk(_that.publicOpenssh,_that.credentialId,_that.application,_that.hasUserVerification,_that.pinSecretId);case DbPreparedAuthRef_PubkeyPkcs11():
return pubkeyPkcs11(_that.publicOpenssh,_that.modulePath,_that.tokenSerial,_that.ckaId,_that.keyType,_that.pinSecretId);case DbPreparedAuthRef_PubkeyEnclave():
return pubkeyEnclave(_that.publicOpenssh,_that.applicationTag);case DbPreparedAuthRef_PubkeyHello():
return pubkeyHello(_that.publicOpenssh,_that.credentialName,_that.keyType);case DbPreparedAuthRef_PubkeyTpm():
return pubkeyTpm(_that.publicOpenssh,_that.provider,_that.blob,_that.cngKeyName,_that.keyType,_that.pinSecretId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String secretId)?  password,TResult? Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult? Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,TResult? Function( String publicOpenssh,  Uint8List credentialId,  String application,  bool hasUserVerification,  String? pinSecretId)?  pubkeySk,TResult? Function( String publicOpenssh,  String modulePath,  String tokenSerial,  Uint8List ckaId,  String keyType,  String? pinSecretId)?  pubkeyPkcs11,TResult? Function( String publicOpenssh,  Uint8List applicationTag)?  pubkeyEnclave,TResult? Function( String publicOpenssh,  String credentialName,  String keyType)?  pubkeyHello,TResult? Function( String publicOpenssh,  String provider,  Uint8List? blob,  String? cngKeyName,  String keyType,  String? pinSecretId)?  pubkeyTpm,}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that.secretId);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeySk() when pubkeySk != null:
return pubkeySk(_that.publicOpenssh,_that.credentialId,_that.application,_that.hasUserVerification,_that.pinSecretId);case DbPreparedAuthRef_PubkeyPkcs11() when pubkeyPkcs11 != null:
return pubkeyPkcs11(_that.publicOpenssh,_that.modulePath,_that.tokenSerial,_that.ckaId,_that.keyType,_that.pinSecretId);case DbPreparedAuthRef_PubkeyEnclave() when pubkeyEnclave != null:
return pubkeyEnclave(_that.publicOpenssh,_that.applicationTag);case DbPreparedAuthRef_PubkeyHello() when pubkeyHello != null:
return pubkeyHello(_that.publicOpenssh,_that.credentialName,_that.keyType);case DbPreparedAuthRef_PubkeyTpm() when pubkeyTpm != null:
return pubkeyTpm(_that.publicOpenssh,_that.provider,_that.blob,_that.cngKeyName,_that.keyType,_that.pinSecretId);case _:
  return null;

}
}

}

/// @nodoc


class DbPreparedAuthRef_Password extends DbPreparedAuthRef {
  const DbPreparedAuthRef_Password({required this.secretId}): super._();
  

 final  String secretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PasswordCopyWith<DbPreparedAuthRef_Password> get copyWith => _$DbPreparedAuthRef_PasswordCopyWithImpl<DbPreparedAuthRef_Password>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_Password&&(identical(other.secretId, secretId) || other.secretId == secretId));
}


@override
int get hashCode => Object.hash(runtimeType,secretId);

@override
String toString() {
  return 'DbPreparedAuthRef.password(secretId: $secretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PasswordCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PasswordCopyWith(DbPreparedAuthRef_Password value, $Res Function(DbPreparedAuthRef_Password) _then) = _$DbPreparedAuthRef_PasswordCopyWithImpl;
@useResult
$Res call({
 String secretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PasswordCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PasswordCopyWith<$Res> {
  _$DbPreparedAuthRef_PasswordCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_Password _self;
  final $Res Function(DbPreparedAuthRef_Password) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? secretId = null,}) {
  return _then(DbPreparedAuthRef_Password(
secretId: null == secretId ? _self.secretId : secretId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_Pubkey extends DbPreparedAuthRef {
  const DbPreparedAuthRef_Pubkey({required this.keySecretId, this.passphraseSecretId}): super._();
  

 final  String keySecretId;
 final  String? passphraseSecretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyCopyWith<DbPreparedAuthRef_Pubkey> get copyWith => _$DbPreparedAuthRef_PubkeyCopyWithImpl<DbPreparedAuthRef_Pubkey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_Pubkey&&(identical(other.keySecretId, keySecretId) || other.keySecretId == keySecretId)&&(identical(other.passphraseSecretId, passphraseSecretId) || other.passphraseSecretId == passphraseSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,keySecretId,passphraseSecretId);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkey(keySecretId: $keySecretId, passphraseSecretId: $passphraseSecretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyCopyWith(DbPreparedAuthRef_Pubkey value, $Res Function(DbPreparedAuthRef_Pubkey) _then) = _$DbPreparedAuthRef_PubkeyCopyWithImpl;
@useResult
$Res call({
 String keySecretId, String? passphraseSecretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_Pubkey _self;
  final $Res Function(DbPreparedAuthRef_Pubkey) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keySecretId = null,Object? passphraseSecretId = freezed,}) {
  return _then(DbPreparedAuthRef_Pubkey(
keySecretId: null == keySecretId ? _self.keySecretId : keySecretId // ignore: cast_nullable_to_non_nullable
as String,passphraseSecretId: freezed == passphraseSecretId ? _self.passphraseSecretId : passphraseSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeyCert extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeyCert({required this.keySecretId, required this.certSecretId, this.passphraseSecretId}): super._();
  

 final  String keySecretId;
 final  String certSecretId;
 final  String? passphraseSecretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyCertCopyWith<DbPreparedAuthRef_PubkeyCert> get copyWith => _$DbPreparedAuthRef_PubkeyCertCopyWithImpl<DbPreparedAuthRef_PubkeyCert>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeyCert&&(identical(other.keySecretId, keySecretId) || other.keySecretId == keySecretId)&&(identical(other.certSecretId, certSecretId) || other.certSecretId == certSecretId)&&(identical(other.passphraseSecretId, passphraseSecretId) || other.passphraseSecretId == passphraseSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,keySecretId,certSecretId,passphraseSecretId);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeyCert(keySecretId: $keySecretId, certSecretId: $certSecretId, passphraseSecretId: $passphraseSecretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyCertCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyCertCopyWith(DbPreparedAuthRef_PubkeyCert value, $Res Function(DbPreparedAuthRef_PubkeyCert) _then) = _$DbPreparedAuthRef_PubkeyCertCopyWithImpl;
@useResult
$Res call({
 String keySecretId, String certSecretId, String? passphraseSecretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyCertCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyCertCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyCertCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeyCert _self;
  final $Res Function(DbPreparedAuthRef_PubkeyCert) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keySecretId = null,Object? certSecretId = null,Object? passphraseSecretId = freezed,}) {
  return _then(DbPreparedAuthRef_PubkeyCert(
keySecretId: null == keySecretId ? _self.keySecretId : keySecretId // ignore: cast_nullable_to_non_nullable
as String,certSecretId: null == certSecretId ? _self.certSecretId : certSecretId // ignore: cast_nullable_to_non_nullable
as String,passphraseSecretId: freezed == passphraseSecretId ? _self.passphraseSecretId : passphraseSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeySk extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeySk({required this.publicOpenssh, required this.credentialId, required this.application, required this.hasUserVerification, this.pinSecretId}): super._();
  

 final  String publicOpenssh;
 final  Uint8List credentialId;
 final  String application;
 final  bool hasUserVerification;
 final  String? pinSecretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeySkCopyWith<DbPreparedAuthRef_PubkeySk> get copyWith => _$DbPreparedAuthRef_PubkeySkCopyWithImpl<DbPreparedAuthRef_PubkeySk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeySk&&(identical(other.publicOpenssh, publicOpenssh) || other.publicOpenssh == publicOpenssh)&&const DeepCollectionEquality().equals(other.credentialId, credentialId)&&(identical(other.application, application) || other.application == application)&&(identical(other.hasUserVerification, hasUserVerification) || other.hasUserVerification == hasUserVerification)&&(identical(other.pinSecretId, pinSecretId) || other.pinSecretId == pinSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,publicOpenssh,const DeepCollectionEquality().hash(credentialId),application,hasUserVerification,pinSecretId);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeySk(publicOpenssh: $publicOpenssh, credentialId: $credentialId, application: $application, hasUserVerification: $hasUserVerification, pinSecretId: $pinSecretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeySkCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeySkCopyWith(DbPreparedAuthRef_PubkeySk value, $Res Function(DbPreparedAuthRef_PubkeySk) _then) = _$DbPreparedAuthRef_PubkeySkCopyWithImpl;
@useResult
$Res call({
 String publicOpenssh, Uint8List credentialId, String application, bool hasUserVerification, String? pinSecretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeySkCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeySkCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeySkCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeySk _self;
  final $Res Function(DbPreparedAuthRef_PubkeySk) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publicOpenssh = null,Object? credentialId = null,Object? application = null,Object? hasUserVerification = null,Object? pinSecretId = freezed,}) {
  return _then(DbPreparedAuthRef_PubkeySk(
publicOpenssh: null == publicOpenssh ? _self.publicOpenssh : publicOpenssh // ignore: cast_nullable_to_non_nullable
as String,credentialId: null == credentialId ? _self.credentialId : credentialId // ignore: cast_nullable_to_non_nullable
as Uint8List,application: null == application ? _self.application : application // ignore: cast_nullable_to_non_nullable
as String,hasUserVerification: null == hasUserVerification ? _self.hasUserVerification : hasUserVerification // ignore: cast_nullable_to_non_nullable
as bool,pinSecretId: freezed == pinSecretId ? _self.pinSecretId : pinSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeyPkcs11 extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeyPkcs11({required this.publicOpenssh, required this.modulePath, required this.tokenSerial, required this.ckaId, required this.keyType, this.pinSecretId}): super._();
  

 final  String publicOpenssh;
 final  String modulePath;
 final  String tokenSerial;
 final  Uint8List ckaId;
 final  String keyType;
 final  String? pinSecretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyPkcs11CopyWith<DbPreparedAuthRef_PubkeyPkcs11> get copyWith => _$DbPreparedAuthRef_PubkeyPkcs11CopyWithImpl<DbPreparedAuthRef_PubkeyPkcs11>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeyPkcs11&&(identical(other.publicOpenssh, publicOpenssh) || other.publicOpenssh == publicOpenssh)&&(identical(other.modulePath, modulePath) || other.modulePath == modulePath)&&(identical(other.tokenSerial, tokenSerial) || other.tokenSerial == tokenSerial)&&const DeepCollectionEquality().equals(other.ckaId, ckaId)&&(identical(other.keyType, keyType) || other.keyType == keyType)&&(identical(other.pinSecretId, pinSecretId) || other.pinSecretId == pinSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,publicOpenssh,modulePath,tokenSerial,const DeepCollectionEquality().hash(ckaId),keyType,pinSecretId);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeyPkcs11(publicOpenssh: $publicOpenssh, modulePath: $modulePath, tokenSerial: $tokenSerial, ckaId: $ckaId, keyType: $keyType, pinSecretId: $pinSecretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyPkcs11CopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyPkcs11CopyWith(DbPreparedAuthRef_PubkeyPkcs11 value, $Res Function(DbPreparedAuthRef_PubkeyPkcs11) _then) = _$DbPreparedAuthRef_PubkeyPkcs11CopyWithImpl;
@useResult
$Res call({
 String publicOpenssh, String modulePath, String tokenSerial, Uint8List ckaId, String keyType, String? pinSecretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyPkcs11CopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyPkcs11CopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyPkcs11CopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeyPkcs11 _self;
  final $Res Function(DbPreparedAuthRef_PubkeyPkcs11) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publicOpenssh = null,Object? modulePath = null,Object? tokenSerial = null,Object? ckaId = null,Object? keyType = null,Object? pinSecretId = freezed,}) {
  return _then(DbPreparedAuthRef_PubkeyPkcs11(
publicOpenssh: null == publicOpenssh ? _self.publicOpenssh : publicOpenssh // ignore: cast_nullable_to_non_nullable
as String,modulePath: null == modulePath ? _self.modulePath : modulePath // ignore: cast_nullable_to_non_nullable
as String,tokenSerial: null == tokenSerial ? _self.tokenSerial : tokenSerial // ignore: cast_nullable_to_non_nullable
as String,ckaId: null == ckaId ? _self.ckaId : ckaId // ignore: cast_nullable_to_non_nullable
as Uint8List,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,pinSecretId: freezed == pinSecretId ? _self.pinSecretId : pinSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeyEnclave extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeyEnclave({required this.publicOpenssh, required this.applicationTag}): super._();
  

 final  String publicOpenssh;
 final  Uint8List applicationTag;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyEnclaveCopyWith<DbPreparedAuthRef_PubkeyEnclave> get copyWith => _$DbPreparedAuthRef_PubkeyEnclaveCopyWithImpl<DbPreparedAuthRef_PubkeyEnclave>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeyEnclave&&(identical(other.publicOpenssh, publicOpenssh) || other.publicOpenssh == publicOpenssh)&&const DeepCollectionEquality().equals(other.applicationTag, applicationTag));
}


@override
int get hashCode => Object.hash(runtimeType,publicOpenssh,const DeepCollectionEquality().hash(applicationTag));

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeyEnclave(publicOpenssh: $publicOpenssh, applicationTag: $applicationTag)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyEnclaveCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyEnclaveCopyWith(DbPreparedAuthRef_PubkeyEnclave value, $Res Function(DbPreparedAuthRef_PubkeyEnclave) _then) = _$DbPreparedAuthRef_PubkeyEnclaveCopyWithImpl;
@useResult
$Res call({
 String publicOpenssh, Uint8List applicationTag
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyEnclaveCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyEnclaveCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyEnclaveCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeyEnclave _self;
  final $Res Function(DbPreparedAuthRef_PubkeyEnclave) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publicOpenssh = null,Object? applicationTag = null,}) {
  return _then(DbPreparedAuthRef_PubkeyEnclave(
publicOpenssh: null == publicOpenssh ? _self.publicOpenssh : publicOpenssh // ignore: cast_nullable_to_non_nullable
as String,applicationTag: null == applicationTag ? _self.applicationTag : applicationTag // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeyHello extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeyHello({required this.publicOpenssh, required this.credentialName, required this.keyType}): super._();
  

 final  String publicOpenssh;
 final  String credentialName;
 final  String keyType;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyHelloCopyWith<DbPreparedAuthRef_PubkeyHello> get copyWith => _$DbPreparedAuthRef_PubkeyHelloCopyWithImpl<DbPreparedAuthRef_PubkeyHello>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeyHello&&(identical(other.publicOpenssh, publicOpenssh) || other.publicOpenssh == publicOpenssh)&&(identical(other.credentialName, credentialName) || other.credentialName == credentialName)&&(identical(other.keyType, keyType) || other.keyType == keyType));
}


@override
int get hashCode => Object.hash(runtimeType,publicOpenssh,credentialName,keyType);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeyHello(publicOpenssh: $publicOpenssh, credentialName: $credentialName, keyType: $keyType)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyHelloCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyHelloCopyWith(DbPreparedAuthRef_PubkeyHello value, $Res Function(DbPreparedAuthRef_PubkeyHello) _then) = _$DbPreparedAuthRef_PubkeyHelloCopyWithImpl;
@useResult
$Res call({
 String publicOpenssh, String credentialName, String keyType
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyHelloCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyHelloCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyHelloCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeyHello _self;
  final $Res Function(DbPreparedAuthRef_PubkeyHello) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publicOpenssh = null,Object? credentialName = null,Object? keyType = null,}) {
  return _then(DbPreparedAuthRef_PubkeyHello(
publicOpenssh: null == publicOpenssh ? _self.publicOpenssh : publicOpenssh // ignore: cast_nullable_to_non_nullable
as String,credentialName: null == credentialName ? _self.credentialName : credentialName // ignore: cast_nullable_to_non_nullable
as String,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbPreparedAuthRef_PubkeyTpm extends DbPreparedAuthRef {
  const DbPreparedAuthRef_PubkeyTpm({required this.publicOpenssh, required this.provider, this.blob, this.cngKeyName, required this.keyType, this.pinSecretId}): super._();
  

 final  String publicOpenssh;
 final  String provider;
 final  Uint8List? blob;
 final  String? cngKeyName;
 final  String keyType;
 final  String? pinSecretId;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbPreparedAuthRef_PubkeyTpmCopyWith<DbPreparedAuthRef_PubkeyTpm> get copyWith => _$DbPreparedAuthRef_PubkeyTpmCopyWithImpl<DbPreparedAuthRef_PubkeyTpm>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbPreparedAuthRef_PubkeyTpm&&(identical(other.publicOpenssh, publicOpenssh) || other.publicOpenssh == publicOpenssh)&&(identical(other.provider, provider) || other.provider == provider)&&const DeepCollectionEquality().equals(other.blob, blob)&&(identical(other.cngKeyName, cngKeyName) || other.cngKeyName == cngKeyName)&&(identical(other.keyType, keyType) || other.keyType == keyType)&&(identical(other.pinSecretId, pinSecretId) || other.pinSecretId == pinSecretId));
}


@override
int get hashCode => Object.hash(runtimeType,publicOpenssh,provider,const DeepCollectionEquality().hash(blob),cngKeyName,keyType,pinSecretId);

@override
String toString() {
  return 'DbPreparedAuthRef.pubkeyTpm(publicOpenssh: $publicOpenssh, provider: $provider, blob: $blob, cngKeyName: $cngKeyName, keyType: $keyType, pinSecretId: $pinSecretId)';
}


}

/// @nodoc
abstract mixin class $DbPreparedAuthRef_PubkeyTpmCopyWith<$Res> implements $DbPreparedAuthRefCopyWith<$Res> {
  factory $DbPreparedAuthRef_PubkeyTpmCopyWith(DbPreparedAuthRef_PubkeyTpm value, $Res Function(DbPreparedAuthRef_PubkeyTpm) _then) = _$DbPreparedAuthRef_PubkeyTpmCopyWithImpl;
@useResult
$Res call({
 String publicOpenssh, String provider, Uint8List? blob, String? cngKeyName, String keyType, String? pinSecretId
});




}
/// @nodoc
class _$DbPreparedAuthRef_PubkeyTpmCopyWithImpl<$Res>
    implements $DbPreparedAuthRef_PubkeyTpmCopyWith<$Res> {
  _$DbPreparedAuthRef_PubkeyTpmCopyWithImpl(this._self, this._then);

  final DbPreparedAuthRef_PubkeyTpm _self;
  final $Res Function(DbPreparedAuthRef_PubkeyTpm) _then;

/// Create a copy of DbPreparedAuthRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publicOpenssh = null,Object? provider = null,Object? blob = freezed,Object? cngKeyName = freezed,Object? keyType = null,Object? pinSecretId = freezed,}) {
  return _then(DbPreparedAuthRef_PubkeyTpm(
publicOpenssh: null == publicOpenssh ? _self.publicOpenssh : publicOpenssh // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String,blob: freezed == blob ? _self.blob : blob // ignore: cast_nullable_to_non_nullable
as Uint8List?,cngKeyName: freezed == cngKeyName ? _self.cngKeyName : cngKeyName // ignore: cast_nullable_to_non_nullable
as String?,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,pinSecretId: freezed == pinSecretId ? _self.pinSecretId : pinSecretId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
