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

 String get payload;
/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusCommandCopyWith<BusCommand> get copyWith => _$BusCommandCopyWithImpl<BusCommand>(this as BusCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusCommand&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,payload);

@override
String toString() {
  return 'BusCommand(payload: $payload)';
}


}

/// @nodoc
abstract mixin class $BusCommandCopyWith<$Res>  {
  factory $BusCommandCopyWith(BusCommand value, $Res Function(BusCommand) _then) = _$BusCommandCopyWithImpl;
@useResult
$Res call({
 String payload
});




}
/// @nodoc
class _$BusCommandCopyWithImpl<$Res>
    implements $BusCommandCopyWith<$Res> {
  _$BusCommandCopyWithImpl(this._self, this._then);

  final BusCommand _self;
  final $Res Function(BusCommand) _then;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? payload = null,}) {
  return _then(_self.copyWith(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusCommand_NoopEcho value)?  noopEcho,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusCommand_NoopEcho value)  noopEcho,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusCommand_NoopEcho value)?  noopEcho,}){
final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  noopEcho,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  noopEcho,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho():
return noopEcho(_that.payload);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  noopEcho,}) {final _that = this;
switch (_that) {
case BusCommand_NoopEcho() when noopEcho != null:
return noopEcho(_that.payload);case _:
  return null;

}
}

}

/// @nodoc


class BusCommand_NoopEcho extends BusCommand {
  const BusCommand_NoopEcho({required this.payload}): super._();
  

@override final  String payload;

/// Create a copy of BusCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
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
@override @useResult
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
@override @pragma('vm:prefer-inline') $Res call({Object? payload = null,}) {
  return _then(BusCommand_NoopEcho(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BusEvent {

 String get payload;
/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BusEventCopyWith<BusEvent> get copyWith => _$BusEventCopyWithImpl<BusEvent>(this as BusEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BusEvent&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,payload);

@override
String toString() {
  return 'BusEvent(payload: $payload)';
}


}

/// @nodoc
abstract mixin class $BusEventCopyWith<$Res>  {
  factory $BusEventCopyWith(BusEvent value, $Res Function(BusEvent) _then) = _$BusEventCopyWithImpl;
@useResult
$Res call({
 String payload
});




}
/// @nodoc
class _$BusEventCopyWithImpl<$Res>
    implements $BusEventCopyWith<$Res> {
  _$BusEventCopyWithImpl(this._self, this._then);

  final BusEvent _self;
  final $Res Function(BusEvent) _then;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? payload = null,}) {
  return _then(_self.copyWith(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BusEvent_Echoed value)?  echoed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BusEvent_Echoed value)  echoed,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BusEvent_Echoed value)?  echoed,}){
final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String payload)?  echoed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String payload)  echoed,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed():
return echoed(_that.payload);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String payload)?  echoed,}) {final _that = this;
switch (_that) {
case BusEvent_Echoed() when echoed != null:
return echoed(_that.payload);case _:
  return null;

}
}

}

/// @nodoc


class BusEvent_Echoed extends BusEvent {
  const BusEvent_Echoed({required this.payload}): super._();
  

@override final  String payload;

/// Create a copy of BusEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
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
@override @useResult
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
@override @pragma('vm:prefer-inline') $Res call({Object? payload = null,}) {
  return _then(BusEvent_Echoed(
payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
