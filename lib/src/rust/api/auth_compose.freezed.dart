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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbPreparedAuthRef_Password value)?  password,TResult Function( DbPreparedAuthRef_Pubkey value)?  pubkey,TResult Function( DbPreparedAuthRef_PubkeyCert value)?  pubkeyCert,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbPreparedAuthRef_Password value)  password,required TResult Function( DbPreparedAuthRef_Pubkey value)  pubkey,required TResult Function( DbPreparedAuthRef_PubkeyCert value)  pubkeyCert,}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password():
return password(_that);case DbPreparedAuthRef_Pubkey():
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert():
return pubkeyCert(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbPreparedAuthRef_Password value)?  password,TResult? Function( DbPreparedAuthRef_Pubkey value)?  pubkey,TResult? Function( DbPreparedAuthRef_PubkeyCert value)?  pubkeyCert,}){
final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String secretId)?  password,TResult Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that.secretId);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String secretId)  password,required TResult Function( String keySecretId,  String? passphraseSecretId)  pubkey,required TResult Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)  pubkeyCert,}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password():
return password(_that.secretId);case DbPreparedAuthRef_Pubkey():
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert():
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String secretId)?  password,TResult? Function( String keySecretId,  String? passphraseSecretId)?  pubkey,TResult? Function( String keySecretId,  String certSecretId,  String? passphraseSecretId)?  pubkeyCert,}) {final _that = this;
switch (_that) {
case DbPreparedAuthRef_Password() when password != null:
return password(_that.secretId);case DbPreparedAuthRef_Pubkey() when pubkey != null:
return pubkey(_that.keySecretId,_that.passphraseSecretId);case DbPreparedAuthRef_PubkeyCert() when pubkeyCert != null:
return pubkeyCert(_that.keySecretId,_that.certSecretId,_that.passphraseSecretId);case _:
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

// dart format on
