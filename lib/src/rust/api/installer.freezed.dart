// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'installer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InstallerLaunchOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InstallerLaunchOutcome()';
}


}

/// @nodoc
class $InstallerLaunchOutcomeCopyWith<$Res>  {
$InstallerLaunchOutcomeCopyWith(InstallerLaunchOutcome _, $Res Function(InstallerLaunchOutcome) __);
}


/// Adds pattern-matching-related methods to [InstallerLaunchOutcome].
extension InstallerLaunchOutcomePatterns on InstallerLaunchOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InstallerLaunchOutcome_Launched value)?  launched,TResult Function( InstallerLaunchOutcome_RefusedUnsafePath value)?  refusedUnsafePath,TResult Function( InstallerLaunchOutcome_UnsupportedPlatform value)?  unsupportedPlatform,TResult Function( InstallerLaunchOutcome_LaunchFailed value)?  launchFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched() when launched != null:
return launched(_that);case InstallerLaunchOutcome_RefusedUnsafePath() when refusedUnsafePath != null:
return refusedUnsafePath(_that);case InstallerLaunchOutcome_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case InstallerLaunchOutcome_LaunchFailed() when launchFailed != null:
return launchFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InstallerLaunchOutcome_Launched value)  launched,required TResult Function( InstallerLaunchOutcome_RefusedUnsafePath value)  refusedUnsafePath,required TResult Function( InstallerLaunchOutcome_UnsupportedPlatform value)  unsupportedPlatform,required TResult Function( InstallerLaunchOutcome_LaunchFailed value)  launchFailed,}){
final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched():
return launched(_that);case InstallerLaunchOutcome_RefusedUnsafePath():
return refusedUnsafePath(_that);case InstallerLaunchOutcome_UnsupportedPlatform():
return unsupportedPlatform(_that);case InstallerLaunchOutcome_LaunchFailed():
return launchFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InstallerLaunchOutcome_Launched value)?  launched,TResult? Function( InstallerLaunchOutcome_RefusedUnsafePath value)?  refusedUnsafePath,TResult? Function( InstallerLaunchOutcome_UnsupportedPlatform value)?  unsupportedPlatform,TResult? Function( InstallerLaunchOutcome_LaunchFailed value)?  launchFailed,}){
final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched() when launched != null:
return launched(_that);case InstallerLaunchOutcome_RefusedUnsafePath() when refusedUnsafePath != null:
return refusedUnsafePath(_that);case InstallerLaunchOutcome_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case InstallerLaunchOutcome_LaunchFailed() when launchFailed != null:
return launchFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  launched,TResult Function()?  refusedUnsafePath,TResult Function()?  unsupportedPlatform,TResult Function( int exitCode,  String stderr)?  launchFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched() when launched != null:
return launched();case InstallerLaunchOutcome_RefusedUnsafePath() when refusedUnsafePath != null:
return refusedUnsafePath();case InstallerLaunchOutcome_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case InstallerLaunchOutcome_LaunchFailed() when launchFailed != null:
return launchFailed(_that.exitCode,_that.stderr);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  launched,required TResult Function()  refusedUnsafePath,required TResult Function()  unsupportedPlatform,required TResult Function( int exitCode,  String stderr)  launchFailed,}) {final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched():
return launched();case InstallerLaunchOutcome_RefusedUnsafePath():
return refusedUnsafePath();case InstallerLaunchOutcome_UnsupportedPlatform():
return unsupportedPlatform();case InstallerLaunchOutcome_LaunchFailed():
return launchFailed(_that.exitCode,_that.stderr);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  launched,TResult? Function()?  refusedUnsafePath,TResult? Function()?  unsupportedPlatform,TResult? Function( int exitCode,  String stderr)?  launchFailed,}) {final _that = this;
switch (_that) {
case InstallerLaunchOutcome_Launched() when launched != null:
return launched();case InstallerLaunchOutcome_RefusedUnsafePath() when refusedUnsafePath != null:
return refusedUnsafePath();case InstallerLaunchOutcome_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case InstallerLaunchOutcome_LaunchFailed() when launchFailed != null:
return launchFailed(_that.exitCode,_that.stderr);case _:
  return null;

}
}

}

/// @nodoc


class InstallerLaunchOutcome_Launched extends InstallerLaunchOutcome {
  const InstallerLaunchOutcome_Launched(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchOutcome_Launched);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InstallerLaunchOutcome.launched()';
}


}




/// @nodoc


class InstallerLaunchOutcome_RefusedUnsafePath extends InstallerLaunchOutcome {
  const InstallerLaunchOutcome_RefusedUnsafePath(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchOutcome_RefusedUnsafePath);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InstallerLaunchOutcome.refusedUnsafePath()';
}


}




/// @nodoc


class InstallerLaunchOutcome_UnsupportedPlatform extends InstallerLaunchOutcome {
  const InstallerLaunchOutcome_UnsupportedPlatform(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchOutcome_UnsupportedPlatform);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InstallerLaunchOutcome.unsupportedPlatform()';
}


}




/// @nodoc


class InstallerLaunchOutcome_LaunchFailed extends InstallerLaunchOutcome {
  const InstallerLaunchOutcome_LaunchFailed({required this.exitCode, required this.stderr}): super._();
  

 final  int exitCode;
 final  String stderr;

/// Create a copy of InstallerLaunchOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallerLaunchOutcome_LaunchFailedCopyWith<InstallerLaunchOutcome_LaunchFailed> get copyWith => _$InstallerLaunchOutcome_LaunchFailedCopyWithImpl<InstallerLaunchOutcome_LaunchFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchOutcome_LaunchFailed&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.stderr, stderr) || other.stderr == stderr));
}


@override
int get hashCode => Object.hash(runtimeType,exitCode,stderr);

@override
String toString() {
  return 'InstallerLaunchOutcome.launchFailed(exitCode: $exitCode, stderr: $stderr)';
}


}

/// @nodoc
abstract mixin class $InstallerLaunchOutcome_LaunchFailedCopyWith<$Res> implements $InstallerLaunchOutcomeCopyWith<$Res> {
  factory $InstallerLaunchOutcome_LaunchFailedCopyWith(InstallerLaunchOutcome_LaunchFailed value, $Res Function(InstallerLaunchOutcome_LaunchFailed) _then) = _$InstallerLaunchOutcome_LaunchFailedCopyWithImpl;
@useResult
$Res call({
 int exitCode, String stderr
});




}
/// @nodoc
class _$InstallerLaunchOutcome_LaunchFailedCopyWithImpl<$Res>
    implements $InstallerLaunchOutcome_LaunchFailedCopyWith<$Res> {
  _$InstallerLaunchOutcome_LaunchFailedCopyWithImpl(this._self, this._then);

  final InstallerLaunchOutcome_LaunchFailed _self;
  final $Res Function(InstallerLaunchOutcome_LaunchFailed) _then;

/// Create a copy of InstallerLaunchOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? exitCode = null,Object? stderr = null,}) {
  return _then(InstallerLaunchOutcome_LaunchFailed(
exitCode: null == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int,stderr: null == stderr ? _self.stderr : stderr // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
