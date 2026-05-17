// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sessions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DbSessionJsonValue {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbSessionJsonValue()';
}


}

/// @nodoc
class $DbSessionJsonValueCopyWith<$Res>  {
$DbSessionJsonValueCopyWith(DbSessionJsonValue _, $Res Function(DbSessionJsonValue) __);
}


/// Adds pattern-matching-related methods to [DbSessionJsonValue].
extension DbSessionJsonValuePatterns on DbSessionJsonValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DbSessionJsonValue_Null value)?  null_,TResult Function( DbSessionJsonValue_Bool value)?  bool,TResult Function( DbSessionJsonValue_Int value)?  int,TResult Function( DbSessionJsonValue_Double value)?  double,TResult Function( DbSessionJsonValue_Text value)?  text,TResult Function( DbSessionJsonValue_Array value)?  array,TResult Function( DbSessionJsonValue_Object value)?  object,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DbSessionJsonValue_Null() when null_ != null:
return null_(_that);case DbSessionJsonValue_Bool() when bool != null:
return bool(_that);case DbSessionJsonValue_Int() when int != null:
return int(_that);case DbSessionJsonValue_Double() when double != null:
return double(_that);case DbSessionJsonValue_Text() when text != null:
return text(_that);case DbSessionJsonValue_Array() when array != null:
return array(_that);case DbSessionJsonValue_Object() when object != null:
return object(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DbSessionJsonValue_Null value)  null_,required TResult Function( DbSessionJsonValue_Bool value)  bool,required TResult Function( DbSessionJsonValue_Int value)  int,required TResult Function( DbSessionJsonValue_Double value)  double,required TResult Function( DbSessionJsonValue_Text value)  text,required TResult Function( DbSessionJsonValue_Array value)  array,required TResult Function( DbSessionJsonValue_Object value)  object,}){
final _that = this;
switch (_that) {
case DbSessionJsonValue_Null():
return null_(_that);case DbSessionJsonValue_Bool():
return bool(_that);case DbSessionJsonValue_Int():
return int(_that);case DbSessionJsonValue_Double():
return double(_that);case DbSessionJsonValue_Text():
return text(_that);case DbSessionJsonValue_Array():
return array(_that);case DbSessionJsonValue_Object():
return object(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DbSessionJsonValue_Null value)?  null_,TResult? Function( DbSessionJsonValue_Bool value)?  bool,TResult? Function( DbSessionJsonValue_Int value)?  int,TResult? Function( DbSessionJsonValue_Double value)?  double,TResult? Function( DbSessionJsonValue_Text value)?  text,TResult? Function( DbSessionJsonValue_Array value)?  array,TResult? Function( DbSessionJsonValue_Object value)?  object,}){
final _that = this;
switch (_that) {
case DbSessionJsonValue_Null() when null_ != null:
return null_(_that);case DbSessionJsonValue_Bool() when bool != null:
return bool(_that);case DbSessionJsonValue_Int() when int != null:
return int(_that);case DbSessionJsonValue_Double() when double != null:
return double(_that);case DbSessionJsonValue_Text() when text != null:
return text(_that);case DbSessionJsonValue_Array() when array != null:
return array(_that);case DbSessionJsonValue_Object() when object != null:
return object(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  null_,TResult Function( bool field0)?  bool,TResult Function( PlatformInt64 field0)?  int,TResult Function( double field0)?  double,TResult Function( String field0)?  text,TResult Function( List<DbSessionJsonValue> field0)?  array,TResult Function( List<DbSessionJsonExtra> field0)?  object,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DbSessionJsonValue_Null() when null_ != null:
return null_();case DbSessionJsonValue_Bool() when bool != null:
return bool(_that.field0);case DbSessionJsonValue_Int() when int != null:
return int(_that.field0);case DbSessionJsonValue_Double() when double != null:
return double(_that.field0);case DbSessionJsonValue_Text() when text != null:
return text(_that.field0);case DbSessionJsonValue_Array() when array != null:
return array(_that.field0);case DbSessionJsonValue_Object() when object != null:
return object(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  null_,required TResult Function( bool field0)  bool,required TResult Function( PlatformInt64 field0)  int,required TResult Function( double field0)  double,required TResult Function( String field0)  text,required TResult Function( List<DbSessionJsonValue> field0)  array,required TResult Function( List<DbSessionJsonExtra> field0)  object,}) {final _that = this;
switch (_that) {
case DbSessionJsonValue_Null():
return null_();case DbSessionJsonValue_Bool():
return bool(_that.field0);case DbSessionJsonValue_Int():
return int(_that.field0);case DbSessionJsonValue_Double():
return double(_that.field0);case DbSessionJsonValue_Text():
return text(_that.field0);case DbSessionJsonValue_Array():
return array(_that.field0);case DbSessionJsonValue_Object():
return object(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  null_,TResult? Function( bool field0)?  bool,TResult? Function( PlatformInt64 field0)?  int,TResult? Function( double field0)?  double,TResult? Function( String field0)?  text,TResult? Function( List<DbSessionJsonValue> field0)?  array,TResult? Function( List<DbSessionJsonExtra> field0)?  object,}) {final _that = this;
switch (_that) {
case DbSessionJsonValue_Null() when null_ != null:
return null_();case DbSessionJsonValue_Bool() when bool != null:
return bool(_that.field0);case DbSessionJsonValue_Int() when int != null:
return int(_that.field0);case DbSessionJsonValue_Double() when double != null:
return double(_that.field0);case DbSessionJsonValue_Text() when text != null:
return text(_that.field0);case DbSessionJsonValue_Array() when array != null:
return array(_that.field0);case DbSessionJsonValue_Object() when object != null:
return object(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DbSessionJsonValue_Null extends DbSessionJsonValue {
  const DbSessionJsonValue_Null(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DbSessionJsonValue.null_()';
}


}




/// @nodoc


class DbSessionJsonValue_Bool extends DbSessionJsonValue {
  const DbSessionJsonValue_Bool(this.field0): super._();
  

 final  bool field0;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_BoolCopyWith<DbSessionJsonValue_Bool> get copyWith => _$DbSessionJsonValue_BoolCopyWithImpl<DbSessionJsonValue_Bool>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Bool&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbSessionJsonValue.bool(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_BoolCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_BoolCopyWith(DbSessionJsonValue_Bool value, $Res Function(DbSessionJsonValue_Bool) _then) = _$DbSessionJsonValue_BoolCopyWithImpl;
@useResult
$Res call({
 bool field0
});




}
/// @nodoc
class _$DbSessionJsonValue_BoolCopyWithImpl<$Res>
    implements $DbSessionJsonValue_BoolCopyWith<$Res> {
  _$DbSessionJsonValue_BoolCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Bool _self;
  final $Res Function(DbSessionJsonValue_Bool) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Bool(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class DbSessionJsonValue_Int extends DbSessionJsonValue {
  const DbSessionJsonValue_Int(this.field0): super._();
  

 final  PlatformInt64 field0;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_IntCopyWith<DbSessionJsonValue_Int> get copyWith => _$DbSessionJsonValue_IntCopyWithImpl<DbSessionJsonValue_Int>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Int&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbSessionJsonValue.int(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_IntCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_IntCopyWith(DbSessionJsonValue_Int value, $Res Function(DbSessionJsonValue_Int) _then) = _$DbSessionJsonValue_IntCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 field0
});




}
/// @nodoc
class _$DbSessionJsonValue_IntCopyWithImpl<$Res>
    implements $DbSessionJsonValue_IntCopyWith<$Res> {
  _$DbSessionJsonValue_IntCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Int _self;
  final $Res Function(DbSessionJsonValue_Int) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Int(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class DbSessionJsonValue_Double extends DbSessionJsonValue {
  const DbSessionJsonValue_Double(this.field0): super._();
  

 final  double field0;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_DoubleCopyWith<DbSessionJsonValue_Double> get copyWith => _$DbSessionJsonValue_DoubleCopyWithImpl<DbSessionJsonValue_Double>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Double&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbSessionJsonValue.double(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_DoubleCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_DoubleCopyWith(DbSessionJsonValue_Double value, $Res Function(DbSessionJsonValue_Double) _then) = _$DbSessionJsonValue_DoubleCopyWithImpl;
@useResult
$Res call({
 double field0
});




}
/// @nodoc
class _$DbSessionJsonValue_DoubleCopyWithImpl<$Res>
    implements $DbSessionJsonValue_DoubleCopyWith<$Res> {
  _$DbSessionJsonValue_DoubleCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Double _self;
  final $Res Function(DbSessionJsonValue_Double) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Double(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class DbSessionJsonValue_Text extends DbSessionJsonValue {
  const DbSessionJsonValue_Text(this.field0): super._();
  

 final  String field0;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_TextCopyWith<DbSessionJsonValue_Text> get copyWith => _$DbSessionJsonValue_TextCopyWithImpl<DbSessionJsonValue_Text>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DbSessionJsonValue.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_TextCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_TextCopyWith(DbSessionJsonValue_Text value, $Res Function(DbSessionJsonValue_Text) _then) = _$DbSessionJsonValue_TextCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DbSessionJsonValue_TextCopyWithImpl<$Res>
    implements $DbSessionJsonValue_TextCopyWith<$Res> {
  _$DbSessionJsonValue_TextCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Text _self;
  final $Res Function(DbSessionJsonValue_Text) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DbSessionJsonValue_Array extends DbSessionJsonValue {
  const DbSessionJsonValue_Array(final  List<DbSessionJsonValue> field0): _field0 = field0,super._();
  

 final  List<DbSessionJsonValue> _field0;
 List<DbSessionJsonValue> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_ArrayCopyWith<DbSessionJsonValue_Array> get copyWith => _$DbSessionJsonValue_ArrayCopyWithImpl<DbSessionJsonValue_Array>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Array&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'DbSessionJsonValue.array(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_ArrayCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_ArrayCopyWith(DbSessionJsonValue_Array value, $Res Function(DbSessionJsonValue_Array) _then) = _$DbSessionJsonValue_ArrayCopyWithImpl;
@useResult
$Res call({
 List<DbSessionJsonValue> field0
});




}
/// @nodoc
class _$DbSessionJsonValue_ArrayCopyWithImpl<$Res>
    implements $DbSessionJsonValue_ArrayCopyWith<$Res> {
  _$DbSessionJsonValue_ArrayCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Array _self;
  final $Res Function(DbSessionJsonValue_Array) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Array(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<DbSessionJsonValue>,
  ));
}


}

/// @nodoc


class DbSessionJsonValue_Object extends DbSessionJsonValue {
  const DbSessionJsonValue_Object(final  List<DbSessionJsonExtra> field0): _field0 = field0,super._();
  

 final  List<DbSessionJsonExtra> _field0;
 List<DbSessionJsonExtra> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DbSessionJsonValue_ObjectCopyWith<DbSessionJsonValue_Object> get copyWith => _$DbSessionJsonValue_ObjectCopyWithImpl<DbSessionJsonValue_Object>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DbSessionJsonValue_Object&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'DbSessionJsonValue.object(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DbSessionJsonValue_ObjectCopyWith<$Res> implements $DbSessionJsonValueCopyWith<$Res> {
  factory $DbSessionJsonValue_ObjectCopyWith(DbSessionJsonValue_Object value, $Res Function(DbSessionJsonValue_Object) _then) = _$DbSessionJsonValue_ObjectCopyWithImpl;
@useResult
$Res call({
 List<DbSessionJsonExtra> field0
});




}
/// @nodoc
class _$DbSessionJsonValue_ObjectCopyWithImpl<$Res>
    implements $DbSessionJsonValue_ObjectCopyWith<$Res> {
  _$DbSessionJsonValue_ObjectCopyWithImpl(this._self, this._then);

  final DbSessionJsonValue_Object _self;
  final $Res Function(DbSessionJsonValue_Object) _then;

/// Create a copy of DbSessionJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DbSessionJsonValue_Object(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<DbSessionJsonExtra>,
  ));
}


}

// dart format on
