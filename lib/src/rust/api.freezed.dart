// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$VaultBiometricError {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultBiometricError_Corrupt value) corrupt,
    required TResult Function(VaultBiometricError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultBiometricError_Wrap value) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult? Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult? Function(VaultBiometricError_Wrap value)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult Function(VaultBiometricError_Wrap value)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VaultBiometricErrorCopyWith<$Res> {
  factory $VaultBiometricErrorCopyWith(
    VaultBiometricError value,
    $Res Function(VaultBiometricError) then,
  ) = _$VaultBiometricErrorCopyWithImpl<$Res, VaultBiometricError>;
}

/// @nodoc
class _$VaultBiometricErrorCopyWithImpl<$Res, $Val extends VaultBiometricError>
    implements $VaultBiometricErrorCopyWith<$Res> {
  _$VaultBiometricErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$VaultBiometricError_CorruptImplCopyWith<$Res> {
  factory _$$VaultBiometricError_CorruptImplCopyWith(
    _$VaultBiometricError_CorruptImpl value,
    $Res Function(_$VaultBiometricError_CorruptImpl) then,
  ) = __$$VaultBiometricError_CorruptImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultBiometricError_CorruptImplCopyWithImpl<$Res>
    extends
        _$VaultBiometricErrorCopyWithImpl<
          $Res,
          _$VaultBiometricError_CorruptImpl
        >
    implements _$$VaultBiometricError_CorruptImplCopyWith<$Res> {
  __$$VaultBiometricError_CorruptImplCopyWithImpl(
    _$VaultBiometricError_CorruptImpl _value,
    $Res Function(_$VaultBiometricError_CorruptImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultBiometricError_CorruptImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultBiometricError_CorruptImpl extends VaultBiometricError_Corrupt {
  const _$VaultBiometricError_CorruptImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultBiometricError.corrupt(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultBiometricError_CorruptImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultBiometricError_CorruptImplCopyWith<_$VaultBiometricError_CorruptImpl>
  get copyWith =>
      __$$VaultBiometricError_CorruptImplCopyWithImpl<
        _$VaultBiometricError_CorruptImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return corrupt(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return corrupt?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultBiometricError_Corrupt value) corrupt,
    required TResult Function(VaultBiometricError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultBiometricError_Wrap value) wrap,
  }) {
    return corrupt(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult? Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult? Function(VaultBiometricError_Wrap value)? wrap,
  }) {
    return corrupt?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult Function(VaultBiometricError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(this);
    }
    return orElse();
  }
}

abstract class VaultBiometricError_Corrupt extends VaultBiometricError {
  const factory VaultBiometricError_Corrupt(final String field0) =
      _$VaultBiometricError_CorruptImpl;
  const VaultBiometricError_Corrupt._() : super._();

  String get field0;

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultBiometricError_CorruptImplCopyWith<_$VaultBiometricError_CorruptImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultBiometricError_WrongPassphraseImplCopyWith<$Res> {
  factory _$$VaultBiometricError_WrongPassphraseImplCopyWith(
    _$VaultBiometricError_WrongPassphraseImpl value,
    $Res Function(_$VaultBiometricError_WrongPassphraseImpl) then,
  ) = __$$VaultBiometricError_WrongPassphraseImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$VaultBiometricError_WrongPassphraseImplCopyWithImpl<$Res>
    extends
        _$VaultBiometricErrorCopyWithImpl<
          $Res,
          _$VaultBiometricError_WrongPassphraseImpl
        >
    implements _$$VaultBiometricError_WrongPassphraseImplCopyWith<$Res> {
  __$$VaultBiometricError_WrongPassphraseImplCopyWithImpl(
    _$VaultBiometricError_WrongPassphraseImpl _value,
    $Res Function(_$VaultBiometricError_WrongPassphraseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$VaultBiometricError_WrongPassphraseImpl
    extends VaultBiometricError_WrongPassphrase {
  const _$VaultBiometricError_WrongPassphraseImpl() : super._();

  @override
  String toString() {
    return 'VaultBiometricError.wrongPassphrase()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultBiometricError_WrongPassphraseImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return wrongPassphrase();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return wrongPassphrase?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultBiometricError_Corrupt value) corrupt,
    required TResult Function(VaultBiometricError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultBiometricError_Wrap value) wrap,
  }) {
    return wrongPassphrase(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult? Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult? Function(VaultBiometricError_Wrap value)? wrap,
  }) {
    return wrongPassphrase?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult Function(VaultBiometricError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase(this);
    }
    return orElse();
  }
}

abstract class VaultBiometricError_WrongPassphrase extends VaultBiometricError {
  const factory VaultBiometricError_WrongPassphrase() =
      _$VaultBiometricError_WrongPassphraseImpl;
  const VaultBiometricError_WrongPassphrase._() : super._();
}

/// @nodoc
abstract class _$$VaultBiometricError_WrapImplCopyWith<$Res> {
  factory _$$VaultBiometricError_WrapImplCopyWith(
    _$VaultBiometricError_WrapImpl value,
    $Res Function(_$VaultBiometricError_WrapImpl) then,
  ) = __$$VaultBiometricError_WrapImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultBiometricError_WrapImplCopyWithImpl<$Res>
    extends
        _$VaultBiometricErrorCopyWithImpl<$Res, _$VaultBiometricError_WrapImpl>
    implements _$$VaultBiometricError_WrapImplCopyWith<$Res> {
  __$$VaultBiometricError_WrapImplCopyWithImpl(
    _$VaultBiometricError_WrapImpl _value,
    $Res Function(_$VaultBiometricError_WrapImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultBiometricError_WrapImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultBiometricError_WrapImpl extends VaultBiometricError_Wrap {
  const _$VaultBiometricError_WrapImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultBiometricError.wrap(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultBiometricError_WrapImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultBiometricError_WrapImplCopyWith<_$VaultBiometricError_WrapImpl>
  get copyWith =>
      __$$VaultBiometricError_WrapImplCopyWithImpl<
        _$VaultBiometricError_WrapImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return wrap(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return wrap?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultBiometricError_Corrupt value) corrupt,
    required TResult Function(VaultBiometricError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultBiometricError_Wrap value) wrap,
  }) {
    return wrap(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult? Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult? Function(VaultBiometricError_Wrap value)? wrap,
  }) {
    return wrap?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultBiometricError_Corrupt value)? corrupt,
    TResult Function(VaultBiometricError_WrongPassphrase value)?
    wrongPassphrase,
    TResult Function(VaultBiometricError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(this);
    }
    return orElse();
  }
}

abstract class VaultBiometricError_Wrap extends VaultBiometricError {
  const factory VaultBiometricError_Wrap(final String field0) =
      _$VaultBiometricError_WrapImpl;
  const VaultBiometricError_Wrap._() : super._();

  String get field0;

  /// Create a copy of VaultBiometricError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultBiometricError_WrapImplCopyWith<_$VaultBiometricError_WrapImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$VaultCreateError {
  String get field0 => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) alreadyExists,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? alreadyExists,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? alreadyExists,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultCreateError_AlreadyExists value)
    alreadyExists,
    required TResult Function(VaultCreateError_VaultOpen value) vaultOpen,
    required TResult Function(VaultCreateError_Wrap value) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult? Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultCreateError_Wrap value)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult Function(VaultCreateError_Wrap value)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $VaultCreateErrorCopyWith<VaultCreateError> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VaultCreateErrorCopyWith<$Res> {
  factory $VaultCreateErrorCopyWith(
    VaultCreateError value,
    $Res Function(VaultCreateError) then,
  ) = _$VaultCreateErrorCopyWithImpl<$Res, VaultCreateError>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$VaultCreateErrorCopyWithImpl<$Res, $Val extends VaultCreateError>
    implements $VaultCreateErrorCopyWith<$Res> {
  _$VaultCreateErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _value.copyWith(
            field0: null == field0
                ? _value.field0
                : field0 // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$VaultCreateError_AlreadyExistsImplCopyWith<$Res>
    implements $VaultCreateErrorCopyWith<$Res> {
  factory _$$VaultCreateError_AlreadyExistsImplCopyWith(
    _$VaultCreateError_AlreadyExistsImpl value,
    $Res Function(_$VaultCreateError_AlreadyExistsImpl) then,
  ) = __$$VaultCreateError_AlreadyExistsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultCreateError_AlreadyExistsImplCopyWithImpl<$Res>
    extends
        _$VaultCreateErrorCopyWithImpl<
          $Res,
          _$VaultCreateError_AlreadyExistsImpl
        >
    implements _$$VaultCreateError_AlreadyExistsImplCopyWith<$Res> {
  __$$VaultCreateError_AlreadyExistsImplCopyWithImpl(
    _$VaultCreateError_AlreadyExistsImpl _value,
    $Res Function(_$VaultCreateError_AlreadyExistsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultCreateError_AlreadyExistsImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultCreateError_AlreadyExistsImpl
    extends VaultCreateError_AlreadyExists {
  const _$VaultCreateError_AlreadyExistsImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultCreateError.alreadyExists(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultCreateError_AlreadyExistsImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultCreateError_AlreadyExistsImplCopyWith<
    _$VaultCreateError_AlreadyExistsImpl
  >
  get copyWith =>
      __$$VaultCreateError_AlreadyExistsImplCopyWithImpl<
        _$VaultCreateError_AlreadyExistsImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) alreadyExists,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) wrap,
  }) {
    return alreadyExists(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? alreadyExists,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? wrap,
  }) {
    return alreadyExists?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? alreadyExists,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (alreadyExists != null) {
      return alreadyExists(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultCreateError_AlreadyExists value)
    alreadyExists,
    required TResult Function(VaultCreateError_VaultOpen value) vaultOpen,
    required TResult Function(VaultCreateError_Wrap value) wrap,
  }) {
    return alreadyExists(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult? Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultCreateError_Wrap value)? wrap,
  }) {
    return alreadyExists?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult Function(VaultCreateError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (alreadyExists != null) {
      return alreadyExists(this);
    }
    return orElse();
  }
}

abstract class VaultCreateError_AlreadyExists extends VaultCreateError {
  const factory VaultCreateError_AlreadyExists(final String field0) =
      _$VaultCreateError_AlreadyExistsImpl;
  const VaultCreateError_AlreadyExists._() : super._();

  @override
  String get field0;

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultCreateError_AlreadyExistsImplCopyWith<
    _$VaultCreateError_AlreadyExistsImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultCreateError_VaultOpenImplCopyWith<$Res>
    implements $VaultCreateErrorCopyWith<$Res> {
  factory _$$VaultCreateError_VaultOpenImplCopyWith(
    _$VaultCreateError_VaultOpenImpl value,
    $Res Function(_$VaultCreateError_VaultOpenImpl) then,
  ) = __$$VaultCreateError_VaultOpenImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultCreateError_VaultOpenImplCopyWithImpl<$Res>
    extends
        _$VaultCreateErrorCopyWithImpl<$Res, _$VaultCreateError_VaultOpenImpl>
    implements _$$VaultCreateError_VaultOpenImplCopyWith<$Res> {
  __$$VaultCreateError_VaultOpenImplCopyWithImpl(
    _$VaultCreateError_VaultOpenImpl _value,
    $Res Function(_$VaultCreateError_VaultOpenImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultCreateError_VaultOpenImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultCreateError_VaultOpenImpl extends VaultCreateError_VaultOpen {
  const _$VaultCreateError_VaultOpenImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultCreateError.vaultOpen(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultCreateError_VaultOpenImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultCreateError_VaultOpenImplCopyWith<_$VaultCreateError_VaultOpenImpl>
  get copyWith =>
      __$$VaultCreateError_VaultOpenImplCopyWithImpl<
        _$VaultCreateError_VaultOpenImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) alreadyExists,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) wrap,
  }) {
    return vaultOpen(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? alreadyExists,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? wrap,
  }) {
    return vaultOpen?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? alreadyExists,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultCreateError_AlreadyExists value)
    alreadyExists,
    required TResult Function(VaultCreateError_VaultOpen value) vaultOpen,
    required TResult Function(VaultCreateError_Wrap value) wrap,
  }) {
    return vaultOpen(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult? Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultCreateError_Wrap value)? wrap,
  }) {
    return vaultOpen?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult Function(VaultCreateError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(this);
    }
    return orElse();
  }
}

abstract class VaultCreateError_VaultOpen extends VaultCreateError {
  const factory VaultCreateError_VaultOpen(final String field0) =
      _$VaultCreateError_VaultOpenImpl;
  const VaultCreateError_VaultOpen._() : super._();

  @override
  String get field0;

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultCreateError_VaultOpenImplCopyWith<_$VaultCreateError_VaultOpenImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultCreateError_WrapImplCopyWith<$Res>
    implements $VaultCreateErrorCopyWith<$Res> {
  factory _$$VaultCreateError_WrapImplCopyWith(
    _$VaultCreateError_WrapImpl value,
    $Res Function(_$VaultCreateError_WrapImpl) then,
  ) = __$$VaultCreateError_WrapImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultCreateError_WrapImplCopyWithImpl<$Res>
    extends _$VaultCreateErrorCopyWithImpl<$Res, _$VaultCreateError_WrapImpl>
    implements _$$VaultCreateError_WrapImplCopyWith<$Res> {
  __$$VaultCreateError_WrapImplCopyWithImpl(
    _$VaultCreateError_WrapImpl _value,
    $Res Function(_$VaultCreateError_WrapImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultCreateError_WrapImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultCreateError_WrapImpl extends VaultCreateError_Wrap {
  const _$VaultCreateError_WrapImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultCreateError.wrap(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultCreateError_WrapImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultCreateError_WrapImplCopyWith<_$VaultCreateError_WrapImpl>
  get copyWith =>
      __$$VaultCreateError_WrapImplCopyWithImpl<_$VaultCreateError_WrapImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) alreadyExists,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) wrap,
  }) {
    return wrap(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? alreadyExists,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? wrap,
  }) {
    return wrap?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? alreadyExists,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultCreateError_AlreadyExists value)
    alreadyExists,
    required TResult Function(VaultCreateError_VaultOpen value) vaultOpen,
    required TResult Function(VaultCreateError_Wrap value) wrap,
  }) {
    return wrap(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult? Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultCreateError_Wrap value)? wrap,
  }) {
    return wrap?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultCreateError_AlreadyExists value)? alreadyExists,
    TResult Function(VaultCreateError_VaultOpen value)? vaultOpen,
    TResult Function(VaultCreateError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(this);
    }
    return orElse();
  }
}

abstract class VaultCreateError_Wrap extends VaultCreateError {
  const factory VaultCreateError_Wrap(final String field0) =
      _$VaultCreateError_WrapImpl;
  const VaultCreateError_Wrap._() : super._();

  @override
  String get field0;

  /// Create a copy of VaultCreateError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultCreateError_WrapImplCopyWith<_$VaultCreateError_WrapImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$VaultRewrapError {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultRewrapError_Corrupt value) corrupt,
    required TResult Function(VaultRewrapError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultRewrapError_Wrap value) wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult? Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultRewrapError_Wrap value)? wrap,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultRewrapError_Wrap value)? wrap,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VaultRewrapErrorCopyWith<$Res> {
  factory $VaultRewrapErrorCopyWith(
    VaultRewrapError value,
    $Res Function(VaultRewrapError) then,
  ) = _$VaultRewrapErrorCopyWithImpl<$Res, VaultRewrapError>;
}

/// @nodoc
class _$VaultRewrapErrorCopyWithImpl<$Res, $Val extends VaultRewrapError>
    implements $VaultRewrapErrorCopyWith<$Res> {
  _$VaultRewrapErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$VaultRewrapError_CorruptImplCopyWith<$Res> {
  factory _$$VaultRewrapError_CorruptImplCopyWith(
    _$VaultRewrapError_CorruptImpl value,
    $Res Function(_$VaultRewrapError_CorruptImpl) then,
  ) = __$$VaultRewrapError_CorruptImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultRewrapError_CorruptImplCopyWithImpl<$Res>
    extends _$VaultRewrapErrorCopyWithImpl<$Res, _$VaultRewrapError_CorruptImpl>
    implements _$$VaultRewrapError_CorruptImplCopyWith<$Res> {
  __$$VaultRewrapError_CorruptImplCopyWithImpl(
    _$VaultRewrapError_CorruptImpl _value,
    $Res Function(_$VaultRewrapError_CorruptImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultRewrapError_CorruptImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultRewrapError_CorruptImpl extends VaultRewrapError_Corrupt {
  const _$VaultRewrapError_CorruptImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultRewrapError.corrupt(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultRewrapError_CorruptImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultRewrapError_CorruptImplCopyWith<_$VaultRewrapError_CorruptImpl>
  get copyWith =>
      __$$VaultRewrapError_CorruptImplCopyWithImpl<
        _$VaultRewrapError_CorruptImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return corrupt(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return corrupt?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultRewrapError_Corrupt value) corrupt,
    required TResult Function(VaultRewrapError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultRewrapError_Wrap value) wrap,
  }) {
    return corrupt(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult? Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultRewrapError_Wrap value)? wrap,
  }) {
    return corrupt?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultRewrapError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(this);
    }
    return orElse();
  }
}

abstract class VaultRewrapError_Corrupt extends VaultRewrapError {
  const factory VaultRewrapError_Corrupt(final String field0) =
      _$VaultRewrapError_CorruptImpl;
  const VaultRewrapError_Corrupt._() : super._();

  String get field0;

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultRewrapError_CorruptImplCopyWith<_$VaultRewrapError_CorruptImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultRewrapError_WrongPassphraseImplCopyWith<$Res> {
  factory _$$VaultRewrapError_WrongPassphraseImplCopyWith(
    _$VaultRewrapError_WrongPassphraseImpl value,
    $Res Function(_$VaultRewrapError_WrongPassphraseImpl) then,
  ) = __$$VaultRewrapError_WrongPassphraseImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$VaultRewrapError_WrongPassphraseImplCopyWithImpl<$Res>
    extends
        _$VaultRewrapErrorCopyWithImpl<
          $Res,
          _$VaultRewrapError_WrongPassphraseImpl
        >
    implements _$$VaultRewrapError_WrongPassphraseImplCopyWith<$Res> {
  __$$VaultRewrapError_WrongPassphraseImplCopyWithImpl(
    _$VaultRewrapError_WrongPassphraseImpl _value,
    $Res Function(_$VaultRewrapError_WrongPassphraseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$VaultRewrapError_WrongPassphraseImpl
    extends VaultRewrapError_WrongPassphrase {
  const _$VaultRewrapError_WrongPassphraseImpl() : super._();

  @override
  String toString() {
    return 'VaultRewrapError.wrongPassphrase()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultRewrapError_WrongPassphraseImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return wrongPassphrase();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return wrongPassphrase?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultRewrapError_Corrupt value) corrupt,
    required TResult Function(VaultRewrapError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultRewrapError_Wrap value) wrap,
  }) {
    return wrongPassphrase(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult? Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultRewrapError_Wrap value)? wrap,
  }) {
    return wrongPassphrase?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultRewrapError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase(this);
    }
    return orElse();
  }
}

abstract class VaultRewrapError_WrongPassphrase extends VaultRewrapError {
  const factory VaultRewrapError_WrongPassphrase() =
      _$VaultRewrapError_WrongPassphraseImpl;
  const VaultRewrapError_WrongPassphrase._() : super._();
}

/// @nodoc
abstract class _$$VaultRewrapError_WrapImplCopyWith<$Res> {
  factory _$$VaultRewrapError_WrapImplCopyWith(
    _$VaultRewrapError_WrapImpl value,
    $Res Function(_$VaultRewrapError_WrapImpl) then,
  ) = __$$VaultRewrapError_WrapImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultRewrapError_WrapImplCopyWithImpl<$Res>
    extends _$VaultRewrapErrorCopyWithImpl<$Res, _$VaultRewrapError_WrapImpl>
    implements _$$VaultRewrapError_WrapImplCopyWith<$Res> {
  __$$VaultRewrapError_WrapImplCopyWithImpl(
    _$VaultRewrapError_WrapImpl _value,
    $Res Function(_$VaultRewrapError_WrapImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultRewrapError_WrapImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultRewrapError_WrapImpl extends VaultRewrapError_Wrap {
  const _$VaultRewrapError_WrapImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultRewrapError.wrap(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultRewrapError_WrapImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultRewrapError_WrapImplCopyWith<_$VaultRewrapError_WrapImpl>
  get copyWith =>
      __$$VaultRewrapError_WrapImplCopyWithImpl<_$VaultRewrapError_WrapImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) wrap,
  }) {
    return wrap(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? wrap,
  }) {
    return wrap?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultRewrapError_Corrupt value) corrupt,
    required TResult Function(VaultRewrapError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultRewrapError_Wrap value) wrap,
  }) {
    return wrap(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult? Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultRewrapError_Wrap value)? wrap,
  }) {
    return wrap?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultRewrapError_Corrupt value)? corrupt,
    TResult Function(VaultRewrapError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultRewrapError_Wrap value)? wrap,
    required TResult orElse(),
  }) {
    if (wrap != null) {
      return wrap(this);
    }
    return orElse();
  }
}

abstract class VaultRewrapError_Wrap extends VaultRewrapError {
  const factory VaultRewrapError_Wrap(final String field0) =
      _$VaultRewrapError_WrapImpl;
  const VaultRewrapError_Wrap._() : super._();

  String get field0;

  /// Create a copy of VaultRewrapError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultRewrapError_WrapImplCopyWith<_$VaultRewrapError_WrapImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$VaultUnlockError {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultUnlockError_Corrupt value) corrupt,
    required TResult Function(VaultUnlockError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultUnlockError_VaultOpen value) vaultOpen,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult? Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultUnlockError_VaultOpen value)? vaultOpen,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultUnlockError_VaultOpen value)? vaultOpen,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VaultUnlockErrorCopyWith<$Res> {
  factory $VaultUnlockErrorCopyWith(
    VaultUnlockError value,
    $Res Function(VaultUnlockError) then,
  ) = _$VaultUnlockErrorCopyWithImpl<$Res, VaultUnlockError>;
}

/// @nodoc
class _$VaultUnlockErrorCopyWithImpl<$Res, $Val extends VaultUnlockError>
    implements $VaultUnlockErrorCopyWith<$Res> {
  _$VaultUnlockErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$VaultUnlockError_CorruptImplCopyWith<$Res> {
  factory _$$VaultUnlockError_CorruptImplCopyWith(
    _$VaultUnlockError_CorruptImpl value,
    $Res Function(_$VaultUnlockError_CorruptImpl) then,
  ) = __$$VaultUnlockError_CorruptImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultUnlockError_CorruptImplCopyWithImpl<$Res>
    extends _$VaultUnlockErrorCopyWithImpl<$Res, _$VaultUnlockError_CorruptImpl>
    implements _$$VaultUnlockError_CorruptImplCopyWith<$Res> {
  __$$VaultUnlockError_CorruptImplCopyWithImpl(
    _$VaultUnlockError_CorruptImpl _value,
    $Res Function(_$VaultUnlockError_CorruptImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultUnlockError_CorruptImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultUnlockError_CorruptImpl extends VaultUnlockError_Corrupt {
  const _$VaultUnlockError_CorruptImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultUnlockError.corrupt(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultUnlockError_CorruptImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultUnlockError_CorruptImplCopyWith<_$VaultUnlockError_CorruptImpl>
  get copyWith =>
      __$$VaultUnlockError_CorruptImplCopyWithImpl<
        _$VaultUnlockError_CorruptImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
  }) {
    return corrupt(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
  }) {
    return corrupt?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultUnlockError_Corrupt value) corrupt,
    required TResult Function(VaultUnlockError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultUnlockError_VaultOpen value) vaultOpen,
  }) {
    return corrupt(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult? Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultUnlockError_VaultOpen value)? vaultOpen,
  }) {
    return corrupt?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultUnlockError_VaultOpen value)? vaultOpen,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(this);
    }
    return orElse();
  }
}

abstract class VaultUnlockError_Corrupt extends VaultUnlockError {
  const factory VaultUnlockError_Corrupt(final String field0) =
      _$VaultUnlockError_CorruptImpl;
  const VaultUnlockError_Corrupt._() : super._();

  String get field0;

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultUnlockError_CorruptImplCopyWith<_$VaultUnlockError_CorruptImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultUnlockError_WrongPassphraseImplCopyWith<$Res> {
  factory _$$VaultUnlockError_WrongPassphraseImplCopyWith(
    _$VaultUnlockError_WrongPassphraseImpl value,
    $Res Function(_$VaultUnlockError_WrongPassphraseImpl) then,
  ) = __$$VaultUnlockError_WrongPassphraseImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$VaultUnlockError_WrongPassphraseImplCopyWithImpl<$Res>
    extends
        _$VaultUnlockErrorCopyWithImpl<
          $Res,
          _$VaultUnlockError_WrongPassphraseImpl
        >
    implements _$$VaultUnlockError_WrongPassphraseImplCopyWith<$Res> {
  __$$VaultUnlockError_WrongPassphraseImplCopyWithImpl(
    _$VaultUnlockError_WrongPassphraseImpl _value,
    $Res Function(_$VaultUnlockError_WrongPassphraseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$VaultUnlockError_WrongPassphraseImpl
    extends VaultUnlockError_WrongPassphrase {
  const _$VaultUnlockError_WrongPassphraseImpl() : super._();

  @override
  String toString() {
    return 'VaultUnlockError.wrongPassphrase()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultUnlockError_WrongPassphraseImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
  }) {
    return wrongPassphrase();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
  }) {
    return wrongPassphrase?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultUnlockError_Corrupt value) corrupt,
    required TResult Function(VaultUnlockError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultUnlockError_VaultOpen value) vaultOpen,
  }) {
    return wrongPassphrase(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult? Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultUnlockError_VaultOpen value)? vaultOpen,
  }) {
    return wrongPassphrase?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultUnlockError_VaultOpen value)? vaultOpen,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase(this);
    }
    return orElse();
  }
}

abstract class VaultUnlockError_WrongPassphrase extends VaultUnlockError {
  const factory VaultUnlockError_WrongPassphrase() =
      _$VaultUnlockError_WrongPassphraseImpl;
  const VaultUnlockError_WrongPassphrase._() : super._();
}

/// @nodoc
abstract class _$$VaultUnlockError_VaultOpenImplCopyWith<$Res> {
  factory _$$VaultUnlockError_VaultOpenImplCopyWith(
    _$VaultUnlockError_VaultOpenImpl value,
    $Res Function(_$VaultUnlockError_VaultOpenImpl) then,
  ) = __$$VaultUnlockError_VaultOpenImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultUnlockError_VaultOpenImplCopyWithImpl<$Res>
    extends
        _$VaultUnlockErrorCopyWithImpl<$Res, _$VaultUnlockError_VaultOpenImpl>
    implements _$$VaultUnlockError_VaultOpenImplCopyWith<$Res> {
  __$$VaultUnlockError_VaultOpenImplCopyWithImpl(
    _$VaultUnlockError_VaultOpenImpl _value,
    $Res Function(_$VaultUnlockError_VaultOpenImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultUnlockError_VaultOpenImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultUnlockError_VaultOpenImpl extends VaultUnlockError_VaultOpen {
  const _$VaultUnlockError_VaultOpenImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultUnlockError.vaultOpen(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultUnlockError_VaultOpenImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultUnlockError_VaultOpenImplCopyWith<_$VaultUnlockError_VaultOpenImpl>
  get copyWith =>
      __$$VaultUnlockError_VaultOpenImplCopyWithImpl<
        _$VaultUnlockError_VaultOpenImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
  }) {
    return vaultOpen(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
  }) {
    return vaultOpen?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultUnlockError_Corrupt value) corrupt,
    required TResult Function(VaultUnlockError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultUnlockError_VaultOpen value) vaultOpen,
  }) {
    return vaultOpen(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult? Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultUnlockError_VaultOpen value)? vaultOpen,
  }) {
    return vaultOpen?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultUnlockError_Corrupt value)? corrupt,
    TResult Function(VaultUnlockError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultUnlockError_VaultOpen value)? vaultOpen,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(this);
    }
    return orElse();
  }
}

abstract class VaultUnlockError_VaultOpen extends VaultUnlockError {
  const factory VaultUnlockError_VaultOpen(final String field0) =
      _$VaultUnlockError_VaultOpenImpl;
  const VaultUnlockError_VaultOpen._() : super._();

  String get field0;

  /// Create a copy of VaultUnlockError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultUnlockError_VaultOpenImplCopyWith<_$VaultUnlockError_VaultOpenImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$VaultWriteError {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VaultWriteErrorCopyWith<$Res> {
  factory $VaultWriteErrorCopyWith(
    VaultWriteError value,
    $Res Function(VaultWriteError) then,
  ) = _$VaultWriteErrorCopyWithImpl<$Res, VaultWriteError>;
}

/// @nodoc
class _$VaultWriteErrorCopyWithImpl<$Res, $Val extends VaultWriteError>
    implements $VaultWriteErrorCopyWith<$Res> {
  _$VaultWriteErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$VaultWriteError_CorruptImplCopyWith<$Res> {
  factory _$$VaultWriteError_CorruptImplCopyWith(
    _$VaultWriteError_CorruptImpl value,
    $Res Function(_$VaultWriteError_CorruptImpl) then,
  ) = __$$VaultWriteError_CorruptImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultWriteError_CorruptImplCopyWithImpl<$Res>
    extends _$VaultWriteErrorCopyWithImpl<$Res, _$VaultWriteError_CorruptImpl>
    implements _$$VaultWriteError_CorruptImplCopyWith<$Res> {
  __$$VaultWriteError_CorruptImplCopyWithImpl(
    _$VaultWriteError_CorruptImpl _value,
    $Res Function(_$VaultWriteError_CorruptImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultWriteError_CorruptImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultWriteError_CorruptImpl extends VaultWriteError_Corrupt {
  const _$VaultWriteError_CorruptImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultWriteError.corrupt(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultWriteError_CorruptImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultWriteError_CorruptImplCopyWith<_$VaultWriteError_CorruptImpl>
  get copyWith =>
      __$$VaultWriteError_CorruptImplCopyWithImpl<
        _$VaultWriteError_CorruptImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) {
    return corrupt(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) {
    return corrupt?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) {
    return corrupt(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) {
    return corrupt?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) {
    if (corrupt != null) {
      return corrupt(this);
    }
    return orElse();
  }
}

abstract class VaultWriteError_Corrupt extends VaultWriteError {
  const factory VaultWriteError_Corrupt(final String field0) =
      _$VaultWriteError_CorruptImpl;
  const VaultWriteError_Corrupt._() : super._();

  String get field0;

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultWriteError_CorruptImplCopyWith<_$VaultWriteError_CorruptImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultWriteError_WrongPassphraseImplCopyWith<$Res> {
  factory _$$VaultWriteError_WrongPassphraseImplCopyWith(
    _$VaultWriteError_WrongPassphraseImpl value,
    $Res Function(_$VaultWriteError_WrongPassphraseImpl) then,
  ) = __$$VaultWriteError_WrongPassphraseImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$VaultWriteError_WrongPassphraseImplCopyWithImpl<$Res>
    extends
        _$VaultWriteErrorCopyWithImpl<
          $Res,
          _$VaultWriteError_WrongPassphraseImpl
        >
    implements _$$VaultWriteError_WrongPassphraseImplCopyWith<$Res> {
  __$$VaultWriteError_WrongPassphraseImplCopyWithImpl(
    _$VaultWriteError_WrongPassphraseImpl _value,
    $Res Function(_$VaultWriteError_WrongPassphraseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$VaultWriteError_WrongPassphraseImpl
    extends VaultWriteError_WrongPassphrase {
  const _$VaultWriteError_WrongPassphraseImpl() : super._();

  @override
  String toString() {
    return 'VaultWriteError.wrongPassphrase()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultWriteError_WrongPassphraseImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) {
    return wrongPassphrase();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) {
    return wrongPassphrase?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) {
    return wrongPassphrase(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) {
    return wrongPassphrase?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) {
    if (wrongPassphrase != null) {
      return wrongPassphrase(this);
    }
    return orElse();
  }
}

abstract class VaultWriteError_WrongPassphrase extends VaultWriteError {
  const factory VaultWriteError_WrongPassphrase() =
      _$VaultWriteError_WrongPassphraseImpl;
  const VaultWriteError_WrongPassphrase._() : super._();
}

/// @nodoc
abstract class _$$VaultWriteError_VaultOpenImplCopyWith<$Res> {
  factory _$$VaultWriteError_VaultOpenImplCopyWith(
    _$VaultWriteError_VaultOpenImpl value,
    $Res Function(_$VaultWriteError_VaultOpenImpl) then,
  ) = __$$VaultWriteError_VaultOpenImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultWriteError_VaultOpenImplCopyWithImpl<$Res>
    extends _$VaultWriteErrorCopyWithImpl<$Res, _$VaultWriteError_VaultOpenImpl>
    implements _$$VaultWriteError_VaultOpenImplCopyWith<$Res> {
  __$$VaultWriteError_VaultOpenImplCopyWithImpl(
    _$VaultWriteError_VaultOpenImpl _value,
    $Res Function(_$VaultWriteError_VaultOpenImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultWriteError_VaultOpenImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultWriteError_VaultOpenImpl extends VaultWriteError_VaultOpen {
  const _$VaultWriteError_VaultOpenImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultWriteError.vaultOpen(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultWriteError_VaultOpenImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultWriteError_VaultOpenImplCopyWith<_$VaultWriteError_VaultOpenImpl>
  get copyWith =>
      __$$VaultWriteError_VaultOpenImplCopyWithImpl<
        _$VaultWriteError_VaultOpenImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) {
    return vaultOpen(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) {
    return vaultOpen?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) {
    return vaultOpen(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) {
    return vaultOpen?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) {
    if (vaultOpen != null) {
      return vaultOpen(this);
    }
    return orElse();
  }
}

abstract class VaultWriteError_VaultOpen extends VaultWriteError {
  const factory VaultWriteError_VaultOpen(final String field0) =
      _$VaultWriteError_VaultOpenImpl;
  const VaultWriteError_VaultOpen._() : super._();

  String get field0;

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultWriteError_VaultOpenImplCopyWith<_$VaultWriteError_VaultOpenImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultWriteError_ConstraintImplCopyWith<$Res> {
  factory _$$VaultWriteError_ConstraintImplCopyWith(
    _$VaultWriteError_ConstraintImpl value,
    $Res Function(_$VaultWriteError_ConstraintImpl) then,
  ) = __$$VaultWriteError_ConstraintImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$VaultWriteError_ConstraintImplCopyWithImpl<$Res>
    extends
        _$VaultWriteErrorCopyWithImpl<$Res, _$VaultWriteError_ConstraintImpl>
    implements _$$VaultWriteError_ConstraintImplCopyWith<$Res> {
  __$$VaultWriteError_ConstraintImplCopyWithImpl(
    _$VaultWriteError_ConstraintImpl _value,
    $Res Function(_$VaultWriteError_ConstraintImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$VaultWriteError_ConstraintImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$VaultWriteError_ConstraintImpl extends VaultWriteError_Constraint {
  const _$VaultWriteError_ConstraintImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'VaultWriteError.constraint(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultWriteError_ConstraintImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VaultWriteError_ConstraintImplCopyWith<_$VaultWriteError_ConstraintImpl>
  get copyWith =>
      __$$VaultWriteError_ConstraintImplCopyWithImpl<
        _$VaultWriteError_ConstraintImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) {
    return constraint(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) {
    return constraint?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) {
    if (constraint != null) {
      return constraint(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) {
    return constraint(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) {
    return constraint?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) {
    if (constraint != null) {
      return constraint(this);
    }
    return orElse();
  }
}

abstract class VaultWriteError_Constraint extends VaultWriteError {
  const factory VaultWriteError_Constraint(final String field0) =
      _$VaultWriteError_ConstraintImpl;
  const VaultWriteError_Constraint._() : super._();

  String get field0;

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VaultWriteError_ConstraintImplCopyWith<_$VaultWriteError_ConstraintImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VaultWriteError_NotFoundImplCopyWith<$Res> {
  factory _$$VaultWriteError_NotFoundImplCopyWith(
    _$VaultWriteError_NotFoundImpl value,
    $Res Function(_$VaultWriteError_NotFoundImpl) then,
  ) = __$$VaultWriteError_NotFoundImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$VaultWriteError_NotFoundImplCopyWithImpl<$Res>
    extends _$VaultWriteErrorCopyWithImpl<$Res, _$VaultWriteError_NotFoundImpl>
    implements _$$VaultWriteError_NotFoundImplCopyWith<$Res> {
  __$$VaultWriteError_NotFoundImplCopyWithImpl(
    _$VaultWriteError_NotFoundImpl _value,
    $Res Function(_$VaultWriteError_NotFoundImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of VaultWriteError
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$VaultWriteError_NotFoundImpl extends VaultWriteError_NotFound {
  const _$VaultWriteError_NotFoundImpl() : super._();

  @override
  String toString() {
    return 'VaultWriteError.notFound()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VaultWriteError_NotFoundImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) corrupt,
    required TResult Function() wrongPassphrase,
    required TResult Function(String field0) vaultOpen,
    required TResult Function(String field0) constraint,
    required TResult Function() notFound,
  }) {
    return notFound();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? corrupt,
    TResult? Function()? wrongPassphrase,
    TResult? Function(String field0)? vaultOpen,
    TResult? Function(String field0)? constraint,
    TResult? Function()? notFound,
  }) {
    return notFound?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? corrupt,
    TResult Function()? wrongPassphrase,
    TResult Function(String field0)? vaultOpen,
    TResult Function(String field0)? constraint,
    TResult Function()? notFound,
    required TResult orElse(),
  }) {
    if (notFound != null) {
      return notFound();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(VaultWriteError_Corrupt value) corrupt,
    required TResult Function(VaultWriteError_WrongPassphrase value)
    wrongPassphrase,
    required TResult Function(VaultWriteError_VaultOpen value) vaultOpen,
    required TResult Function(VaultWriteError_Constraint value) constraint,
    required TResult Function(VaultWriteError_NotFound value) notFound,
  }) {
    return notFound(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(VaultWriteError_Corrupt value)? corrupt,
    TResult? Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult? Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult? Function(VaultWriteError_Constraint value)? constraint,
    TResult? Function(VaultWriteError_NotFound value)? notFound,
  }) {
    return notFound?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(VaultWriteError_Corrupt value)? corrupt,
    TResult Function(VaultWriteError_WrongPassphrase value)? wrongPassphrase,
    TResult Function(VaultWriteError_VaultOpen value)? vaultOpen,
    TResult Function(VaultWriteError_Constraint value)? constraint,
    TResult Function(VaultWriteError_NotFound value)? notFound,
    required TResult orElse(),
  }) {
    if (notFound != null) {
      return notFound(this);
    }
    return orElse();
  }
}

abstract class VaultWriteError_NotFound extends VaultWriteError {
  const factory VaultWriteError_NotFound() = _$VaultWriteError_NotFoundImpl;
  const VaultWriteError_NotFound._() : super._();
}
