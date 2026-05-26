// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'deeplink.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbDeeplinkOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbDeeplinkOutcome()';
}


}

/// @nodoc
class $DbDeeplinkOutcomeCopyWith<$Res>  {
$DbDeeplinkOutcomeCopyWith(DbDeeplinkOutcome _, $Res Function(DbDeeplinkOutcome) __);
}


/// Adds pattern-matching-related methods to [DbDeeplinkOutcome].
extension DbDeeplinkOutcomePatterns on DbDeeplinkOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbDeeplinkOutcome_Connect value)?  connect,TResult Function( DbDeeplinkOutcome_QrImport value)?  qrImport,TResult Function( DbDeeplinkOutcome_QrImportRejected value)?  qrImportRejected,TResult Function( DbDeeplinkOutcome_Unknown value)?  unknown,TResult Function( DbDeeplinkOutcome_Duplicate value)?  duplicate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect() when connect != null:
return connect(_that);case DbDeeplinkOutcome_QrImport() when qrImport != null:
return qrImport(_that);case DbDeeplinkOutcome_QrImportRejected() when qrImportRejected != null:
return qrImportRejected(_that);case DbDeeplinkOutcome_Unknown() when unknown != null:
return unknown(_that);case DbDeeplinkOutcome_Duplicate() when duplicate != null:
return duplicate(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbDeeplinkOutcome_Connect value)  connect,required TResult Function( DbDeeplinkOutcome_QrImport value)  qrImport,required TResult Function( DbDeeplinkOutcome_QrImportRejected value)  qrImportRejected,required TResult Function( DbDeeplinkOutcome_Unknown value)  unknown,required TResult Function( DbDeeplinkOutcome_Duplicate value)  duplicate,}){
final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect():
return connect(_that);case DbDeeplinkOutcome_QrImport():
return qrImport(_that);case DbDeeplinkOutcome_QrImportRejected():
return qrImportRejected(_that);case DbDeeplinkOutcome_Unknown():
return unknown(_that);case DbDeeplinkOutcome_Duplicate():
return duplicate(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbDeeplinkOutcome_Connect value)?  connect,TResult? Function( DbDeeplinkOutcome_QrImport value)?  qrImport,TResult? Function( DbDeeplinkOutcome_QrImportRejected value)?  qrImportRejected,TResult? Function( DbDeeplinkOutcome_Unknown value)?  unknown,TResult? Function( DbDeeplinkOutcome_Duplicate value)?  duplicate,}){
final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect() when connect != null:
return connect(_that);case DbDeeplinkOutcome_QrImport() when qrImport != null:
return qrImport(_that);case DbDeeplinkOutcome_QrImportRejected() when qrImportRejected != null:
return qrImportRejected(_that);case DbDeeplinkOutcome_Unknown() when unknown != null:
return unknown(_that);case DbDeeplinkOutcome_Duplicate() when duplicate != null:
return duplicate(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String host,  int port,  String user)?  connect,TResult Function( String handleId,  DbImportPreview preview)?  qrImport,TResult Function( PlatformInt64 found,  PlatformInt64 supported)?  qrImportRejected,TResult Function()?  unknown,TResult Function()?  duplicate,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect() when connect != null:
return connect(_that.host,_that.port,_that.user);case DbDeeplinkOutcome_QrImport() when qrImport != null:
return qrImport(_that.handleId,_that.preview);case DbDeeplinkOutcome_QrImportRejected() when qrImportRejected != null:
return qrImportRejected(_that.found,_that.supported);case DbDeeplinkOutcome_Unknown() when unknown != null:
return unknown();case DbDeeplinkOutcome_Duplicate() when duplicate != null:
return duplicate();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String host,  int port,  String user)  connect,required TResult Function( String handleId,  DbImportPreview preview)  qrImport,required TResult Function( PlatformInt64 found,  PlatformInt64 supported)  qrImportRejected,required TResult Function()  unknown,required TResult Function()  duplicate,}) {final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect():
return connect(_that.host,_that.port,_that.user);case DbDeeplinkOutcome_QrImport():
return qrImport(_that.handleId,_that.preview);case DbDeeplinkOutcome_QrImportRejected():
return qrImportRejected(_that.found,_that.supported);case DbDeeplinkOutcome_Unknown():
return unknown();case DbDeeplinkOutcome_Duplicate():
return duplicate();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String host,  int port,  String user)?  connect,TResult? Function( String handleId,  DbImportPreview preview)?  qrImport,TResult? Function( PlatformInt64 found,  PlatformInt64 supported)?  qrImportRejected,TResult? Function()?  unknown,TResult? Function()?  duplicate,}) {final _that = this;
switch (_that) {
case DbDeeplinkOutcome_Connect() when connect != null:
return connect(_that.host,_that.port,_that.user);case DbDeeplinkOutcome_QrImport() when qrImport != null:
return qrImport(_that.handleId,_that.preview);case DbDeeplinkOutcome_QrImportRejected() when qrImportRejected != null:
return qrImportRejected(_that.found,_that.supported);case DbDeeplinkOutcome_Unknown() when unknown != null:
return unknown();case DbDeeplinkOutcome_Duplicate() when duplicate != null:
return duplicate();case _:
  return null;

}
}

}

/// @nodoc


class DbDeeplinkOutcome_Connect extends DbDeeplinkOutcome {
  const DbDeeplinkOutcome_Connect({required this.host, required this.port, required this.user}): super._();
  

 final  String host;
 final  int port;
 final  String user;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbDeeplinkOutcome_ConnectCopyWith<DbDeeplinkOutcome_Connect> get copyWith => _$DbDeeplinkOutcome_ConnectCopyWithImpl<DbDeeplinkOutcome_Connect>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome_Connect&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.user, user) || other.user == user));
}


@override
int get hashCode => Object.hash(runtimeType,host,port,user);

@override
String toString() {
  return 'DbDeeplinkOutcome.connect(host: $host, port: $port, user: $user)';
}


}

/// @nodoc
abstract mixin class $DbDeeplinkOutcome_ConnectCopyWith<$Res> implements $DbDeeplinkOutcomeCopyWith<$Res> {
  factory $DbDeeplinkOutcome_ConnectCopyWith(DbDeeplinkOutcome_Connect value, $Res Function(DbDeeplinkOutcome_Connect) _then) = _$DbDeeplinkOutcome_ConnectCopyWithImpl;
@useResult
$Res call({
 String host, int port, String user
});




}
/// @nodoc
class _$DbDeeplinkOutcome_ConnectCopyWithImpl<$Res>
    implements $DbDeeplinkOutcome_ConnectCopyWith<$Res> {
  _$DbDeeplinkOutcome_ConnectCopyWithImpl(this._self, this._then);

  final DbDeeplinkOutcome_Connect _self;
  final $Res Function(DbDeeplinkOutcome_Connect) _then;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? port = null,Object? user = null,}) {
  return _then(DbDeeplinkOutcome_Connect(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbDeeplinkOutcome_QrImport extends DbDeeplinkOutcome {
  const DbDeeplinkOutcome_QrImport({required this.handleId, required this.preview}): super._();
  

 final  String handleId;
 final  DbImportPreview preview;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbDeeplinkOutcome_QrImportCopyWith<DbDeeplinkOutcome_QrImport> get copyWith => _$DbDeeplinkOutcome_QrImportCopyWithImpl<DbDeeplinkOutcome_QrImport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome_QrImport&&(identical(other.handleId, handleId) || other.handleId == handleId)&&(identical(other.preview, preview) || other.preview == preview));
}


@override
int get hashCode => Object.hash(runtimeType,handleId,preview);

@override
String toString() {
  return 'DbDeeplinkOutcome.qrImport(handleId: $handleId, preview: $preview)';
}


}

/// @nodoc
abstract mixin class $DbDeeplinkOutcome_QrImportCopyWith<$Res> implements $DbDeeplinkOutcomeCopyWith<$Res> {
  factory $DbDeeplinkOutcome_QrImportCopyWith(DbDeeplinkOutcome_QrImport value, $Res Function(DbDeeplinkOutcome_QrImport) _then) = _$DbDeeplinkOutcome_QrImportCopyWithImpl;
@useResult
$Res call({
 String handleId, DbImportPreview preview
});




}
/// @nodoc
class _$DbDeeplinkOutcome_QrImportCopyWithImpl<$Res>
    implements $DbDeeplinkOutcome_QrImportCopyWith<$Res> {
  _$DbDeeplinkOutcome_QrImportCopyWithImpl(this._self, this._then);

  final DbDeeplinkOutcome_QrImport _self;
  final $Res Function(DbDeeplinkOutcome_QrImport) _then;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handleId = null,Object? preview = null,}) {
  return _then(DbDeeplinkOutcome_QrImport(
handleId: null == handleId ? _self.handleId : handleId // ignore: cast_nullable_to_non_nullable
as String,preview: null == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as DbImportPreview,
  ));
}


}

/// @nodoc


class DbDeeplinkOutcome_QrImportRejected extends DbDeeplinkOutcome {
  const DbDeeplinkOutcome_QrImportRejected({required this.found, required this.supported}): super._();
  

 final  PlatformInt64 found;
 final  PlatformInt64 supported;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbDeeplinkOutcome_QrImportRejectedCopyWith<DbDeeplinkOutcome_QrImportRejected> get copyWith => _$DbDeeplinkOutcome_QrImportRejectedCopyWithImpl<DbDeeplinkOutcome_QrImportRejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome_QrImportRejected&&(identical(other.found, found) || other.found == found)&&(identical(other.supported, supported) || other.supported == supported));
}


@override
int get hashCode => Object.hash(runtimeType,found,supported);

@override
String toString() {
  return 'DbDeeplinkOutcome.qrImportRejected(found: $found, supported: $supported)';
}


}

/// @nodoc
abstract mixin class $DbDeeplinkOutcome_QrImportRejectedCopyWith<$Res> implements $DbDeeplinkOutcomeCopyWith<$Res> {
  factory $DbDeeplinkOutcome_QrImportRejectedCopyWith(DbDeeplinkOutcome_QrImportRejected value, $Res Function(DbDeeplinkOutcome_QrImportRejected) _then) = _$DbDeeplinkOutcome_QrImportRejectedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 found, PlatformInt64 supported
});




}
/// @nodoc
class _$DbDeeplinkOutcome_QrImportRejectedCopyWithImpl<$Res>
    implements $DbDeeplinkOutcome_QrImportRejectedCopyWith<$Res> {
  _$DbDeeplinkOutcome_QrImportRejectedCopyWithImpl(this._self, this._then);

  final DbDeeplinkOutcome_QrImportRejected _self;
  final $Res Function(DbDeeplinkOutcome_QrImportRejected) _then;

/// Create a copy of DbDeeplinkOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? found = null,Object? supported = null,}) {
  return _then(DbDeeplinkOutcome_QrImportRejected(
found: null == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as PlatformInt64,supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class DbDeeplinkOutcome_Unknown extends DbDeeplinkOutcome {
  const DbDeeplinkOutcome_Unknown(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbDeeplinkOutcome.unknown()';
}


}




/// @nodoc


class DbDeeplinkOutcome_Duplicate extends DbDeeplinkOutcome {
  const DbDeeplinkOutcome_Duplicate(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbDeeplinkOutcome_Duplicate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbDeeplinkOutcome.duplicate()';
}


}




// dart format on
