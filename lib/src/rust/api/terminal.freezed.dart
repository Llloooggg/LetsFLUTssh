// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'terminal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TerminalUiEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TerminalUiEvent()';
}


}

/// @nodoc
class $TerminalUiEventCopyWith<$Res>  {
$TerminalUiEventCopyWith(TerminalUiEvent _, $Res Function(TerminalUiEvent) __);
}


/// Adds pattern-matching-related methods to [TerminalUiEvent].
extension TerminalUiEventPatterns on TerminalUiEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TerminalUiEvent_Wakeup value)?  wakeup,TResult Function( TerminalUiEvent_Bell value)?  bell,TResult Function( TerminalUiEvent_Title value)?  title,TResult Function( TerminalUiEvent_ResetTitle value)?  resetTitle,TResult Function( TerminalUiEvent_ClipboardStore value)?  clipboardStore,TResult Function( TerminalUiEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup() when wakeup != null:
return wakeup(_that);case TerminalUiEvent_Bell() when bell != null:
return bell(_that);case TerminalUiEvent_Title() when title != null:
return title(_that);case TerminalUiEvent_ResetTitle() when resetTitle != null:
return resetTitle(_that);case TerminalUiEvent_ClipboardStore() when clipboardStore != null:
return clipboardStore(_that);case TerminalUiEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TerminalUiEvent_Wakeup value)  wakeup,required TResult Function( TerminalUiEvent_Bell value)  bell,required TResult Function( TerminalUiEvent_Title value)  title,required TResult Function( TerminalUiEvent_ResetTitle value)  resetTitle,required TResult Function( TerminalUiEvent_ClipboardStore value)  clipboardStore,required TResult Function( TerminalUiEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup():
return wakeup(_that);case TerminalUiEvent_Bell():
return bell(_that);case TerminalUiEvent_Title():
return title(_that);case TerminalUiEvent_ResetTitle():
return resetTitle(_that);case TerminalUiEvent_ClipboardStore():
return clipboardStore(_that);case TerminalUiEvent_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TerminalUiEvent_Wakeup value)?  wakeup,TResult? Function( TerminalUiEvent_Bell value)?  bell,TResult? Function( TerminalUiEvent_Title value)?  title,TResult? Function( TerminalUiEvent_ResetTitle value)?  resetTitle,TResult? Function( TerminalUiEvent_ClipboardStore value)?  clipboardStore,TResult? Function( TerminalUiEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup() when wakeup != null:
return wakeup(_that);case TerminalUiEvent_Bell() when bell != null:
return bell(_that);case TerminalUiEvent_Title() when title != null:
return title(_that);case TerminalUiEvent_ResetTitle() when resetTitle != null:
return resetTitle(_that);case TerminalUiEvent_ClipboardStore() when clipboardStore != null:
return clipboardStore(_that);case TerminalUiEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  wakeup,TResult Function()?  bell,TResult Function( String title)?  title,TResult Function()?  resetTitle,TResult Function( String text)?  clipboardStore,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup() when wakeup != null:
return wakeup();case TerminalUiEvent_Bell() when bell != null:
return bell();case TerminalUiEvent_Title() when title != null:
return title(_that.title);case TerminalUiEvent_ResetTitle() when resetTitle != null:
return resetTitle();case TerminalUiEvent_ClipboardStore() when clipboardStore != null:
return clipboardStore(_that.text);case TerminalUiEvent_Closed() when closed != null:
return closed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  wakeup,required TResult Function()  bell,required TResult Function( String title)  title,required TResult Function()  resetTitle,required TResult Function( String text)  clipboardStore,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup():
return wakeup();case TerminalUiEvent_Bell():
return bell();case TerminalUiEvent_Title():
return title(_that.title);case TerminalUiEvent_ResetTitle():
return resetTitle();case TerminalUiEvent_ClipboardStore():
return clipboardStore(_that.text);case TerminalUiEvent_Closed():
return closed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  wakeup,TResult? Function()?  bell,TResult? Function( String title)?  title,TResult? Function()?  resetTitle,TResult? Function( String text)?  clipboardStore,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case TerminalUiEvent_Wakeup() when wakeup != null:
return wakeup();case TerminalUiEvent_Bell() when bell != null:
return bell();case TerminalUiEvent_Title() when title != null:
return title(_that.title);case TerminalUiEvent_ResetTitle() when resetTitle != null:
return resetTitle();case TerminalUiEvent_ClipboardStore() when clipboardStore != null:
return clipboardStore(_that.text);case TerminalUiEvent_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class TerminalUiEvent_Wakeup extends TerminalUiEvent {
  const TerminalUiEvent_Wakeup(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_Wakeup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TerminalUiEvent.wakeup()';
}


}




/// @nodoc


class TerminalUiEvent_Bell extends TerminalUiEvent {
  const TerminalUiEvent_Bell(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_Bell);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TerminalUiEvent.bell()';
}


}




/// @nodoc


class TerminalUiEvent_Title extends TerminalUiEvent {
  const TerminalUiEvent_Title({required this.title}): super._();
  

 final  String title;

/// Create a copy of TerminalUiEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TerminalUiEvent_TitleCopyWith<TerminalUiEvent_Title> get copyWith => _$TerminalUiEvent_TitleCopyWithImpl<TerminalUiEvent_Title>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_Title&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,title);

@override
String toString() {
  return 'TerminalUiEvent.title(title: $title)';
}


}

/// @nodoc
abstract mixin class $TerminalUiEvent_TitleCopyWith<$Res> implements $TerminalUiEventCopyWith<$Res> {
  factory $TerminalUiEvent_TitleCopyWith(TerminalUiEvent_Title value, $Res Function(TerminalUiEvent_Title) _then) = _$TerminalUiEvent_TitleCopyWithImpl;
@useResult
$Res call({
 String title
});




}
/// @nodoc
class _$TerminalUiEvent_TitleCopyWithImpl<$Res>
    implements $TerminalUiEvent_TitleCopyWith<$Res> {
  _$TerminalUiEvent_TitleCopyWithImpl(this._self, this._then);

  final TerminalUiEvent_Title _self;
  final $Res Function(TerminalUiEvent_Title) _then;

/// Create a copy of TerminalUiEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,}) {
  return _then(TerminalUiEvent_Title(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TerminalUiEvent_ResetTitle extends TerminalUiEvent {
  const TerminalUiEvent_ResetTitle(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_ResetTitle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TerminalUiEvent.resetTitle()';
}


}




/// @nodoc


class TerminalUiEvent_ClipboardStore extends TerminalUiEvent {
  const TerminalUiEvent_ClipboardStore({required this.text}): super._();
  

 final  String text;

/// Create a copy of TerminalUiEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TerminalUiEvent_ClipboardStoreCopyWith<TerminalUiEvent_ClipboardStore> get copyWith => _$TerminalUiEvent_ClipboardStoreCopyWithImpl<TerminalUiEvent_ClipboardStore>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_ClipboardStore&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'TerminalUiEvent.clipboardStore(text: $text)';
}


}

/// @nodoc
abstract mixin class $TerminalUiEvent_ClipboardStoreCopyWith<$Res> implements $TerminalUiEventCopyWith<$Res> {
  factory $TerminalUiEvent_ClipboardStoreCopyWith(TerminalUiEvent_ClipboardStore value, $Res Function(TerminalUiEvent_ClipboardStore) _then) = _$TerminalUiEvent_ClipboardStoreCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$TerminalUiEvent_ClipboardStoreCopyWithImpl<$Res>
    implements $TerminalUiEvent_ClipboardStoreCopyWith<$Res> {
  _$TerminalUiEvent_ClipboardStoreCopyWithImpl(this._self, this._then);

  final TerminalUiEvent_ClipboardStore _self;
  final $Res Function(TerminalUiEvent_ClipboardStore) _then;

/// Create a copy of TerminalUiEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(TerminalUiEvent_ClipboardStore(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TerminalUiEvent_Closed extends TerminalUiEvent {
  const TerminalUiEvent_Closed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TerminalUiEvent_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TerminalUiEvent.closed()';
}


}




// dart format on
