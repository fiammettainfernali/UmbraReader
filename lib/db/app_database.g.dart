// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ReadingProgressRowsTable extends ReadingProgressRows
    with TableInfo<$ReadingProgressRowsTable, ReadingProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _volumeKeyMeta = const VerificationMeta(
    'volumeKey',
  );
  @override
  late final GeneratedColumn<String> volumeKey = GeneratedColumn<String>(
    'volume_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _blockIndexMeta = const VerificationMeta(
    'blockIndex',
  );
  @override
  late final GeneratedColumn<int> blockIndex = GeneratedColumn<int>(
    'block_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _blockCharMeta = const VerificationMeta(
    'blockChar',
  );
  @override
  late final GeneratedColumn<int> blockChar = GeneratedColumn<int>(
    'block_char',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterPathMeta = const VerificationMeta(
    'chapterPath',
  );
  @override
  late final GeneratedColumn<String> chapterPath = GeneratedColumn<String>(
    'chapter_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterCountMeta = const VerificationMeta(
    'chapterCount',
  );
  @override
  late final GeneratedColumn<int> chapterCount = GeneratedColumn<int>(
    'chapter_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endReachedMeta = const VerificationMeta(
    'endReached',
  );
  @override
  late final GeneratedColumn<bool> endReached = GeneratedColumn<bool>(
    'end_reached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("end_reached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _volumeJsonMeta = const VerificationMeta(
    'volumeJson',
  );
  @override
  late final GeneratedColumn<String> volumeJson = GeneratedColumn<String>(
    'volume_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hiddenAtMeta = const VerificationMeta(
    'hiddenAt',
  );
  @override
  late final GeneratedColumn<String> hiddenAt = GeneratedColumn<String>(
    'hidden_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ttsResumeMeta = const VerificationMeta(
    'ttsResume',
  );
  @override
  late final GeneratedColumn<String> ttsResume = GeneratedColumn<String>(
    'tts_resume',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    volumeKey,
    chapterIndex,
    blockIndex,
    blockChar,
    chapterPath,
    chapterCount,
    updatedAt,
    endReached,
    volumeJson,
    hidden,
    hiddenAt,
    ttsResume,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('volume_key')) {
      context.handle(
        _volumeKeyMeta,
        volumeKey.isAcceptableOrUnknown(data['volume_key']!, _volumeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeKeyMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('block_index')) {
      context.handle(
        _blockIndexMeta,
        blockIndex.isAcceptableOrUnknown(data['block_index']!, _blockIndexMeta),
      );
    }
    if (data.containsKey('block_char')) {
      context.handle(
        _blockCharMeta,
        blockChar.isAcceptableOrUnknown(data['block_char']!, _blockCharMeta),
      );
    }
    if (data.containsKey('chapter_path')) {
      context.handle(
        _chapterPathMeta,
        chapterPath.isAcceptableOrUnknown(
          data['chapter_path']!,
          _chapterPathMeta,
        ),
      );
    }
    if (data.containsKey('chapter_count')) {
      context.handle(
        _chapterCountMeta,
        chapterCount.isAcceptableOrUnknown(
          data['chapter_count']!,
          _chapterCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('end_reached')) {
      context.handle(
        _endReachedMeta,
        endReached.isAcceptableOrUnknown(data['end_reached']!, _endReachedMeta),
      );
    }
    if (data.containsKey('volume_json')) {
      context.handle(
        _volumeJsonMeta,
        volumeJson.isAcceptableOrUnknown(data['volume_json']!, _volumeJsonMeta),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    if (data.containsKey('hidden_at')) {
      context.handle(
        _hiddenAtMeta,
        hiddenAt.isAcceptableOrUnknown(data['hidden_at']!, _hiddenAtMeta),
      );
    }
    if (data.containsKey('tts_resume')) {
      context.handle(
        _ttsResumeMeta,
        ttsResume.isAcceptableOrUnknown(data['tts_resume']!, _ttsResumeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {volumeKey};
  @override
  ReadingProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressRow(
      volumeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_key'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      blockIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_index'],
      )!,
      blockChar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_char'],
      )!,
      chapterPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_path'],
      ),
      chapterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
      endReached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}end_reached'],
      )!,
      volumeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_json'],
      ),
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      hiddenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hidden_at'],
      ),
      ttsResume: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tts_resume'],
      ),
    );
  }

  @override
  $ReadingProgressRowsTable createAlias(String alias) {
    return $ReadingProgressRowsTable(attachedDatabase, alias);
  }
}

class ReadingProgressRow extends DataClass
    implements Insertable<ReadingProgressRow> {
  /// `seriesOpdsId/fileName` — the same composite key the prefs store used.
  final String volumeKey;
  final int chapterIndex;
  final int blockIndex;

  /// Character offset of the first visible line within the block — Kindle
  /// "location" / EPUB-CFI-style precision, so a stop mid-way through a
  /// huge webnovel paragraph restores to the exact line, not the
  /// paragraph top.
  final int blockChar;

  /// The chapter's spine href at save time. If a recompiled volume shifts
  /// chapter indexes, the reader re-finds the chapter by path.
  final String? chapterPath;
  final int chapterCount;
  final String? updatedAt;
  final bool endReached;

  /// JSON snapshot of the [Volume] so shelves can list books without the
  /// OPDS feed. Null for rows created by hide/resume before a real read.
  final String? volumeJson;

  /// Hidden from the "Continue reading" shelf (position still kept).
  final bool hidden;

  /// When [hidden] last changed, so the flag can be merged across devices.
  ///
  /// Separate from [updatedAt] because they answer different questions and
  /// move at different times: [updatedAt] is when the *position* last
  /// changed, and reusing it would both make hiding look like reading and
  /// let any position write undo a removal. Null on rows whose shelf state
  /// has never been touched, which loses to any device that has an opinion.
  final String? hiddenAt;

  /// Read-aloud word-exact resume point, "blockIndex:charOffset". Device
  /// local and ephemeral — never synced.
  final String? ttsResume;
  const ReadingProgressRow({
    required this.volumeKey,
    required this.chapterIndex,
    required this.blockIndex,
    required this.blockChar,
    this.chapterPath,
    required this.chapterCount,
    this.updatedAt,
    required this.endReached,
    this.volumeJson,
    required this.hidden,
    this.hiddenAt,
    this.ttsResume,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['volume_key'] = Variable<String>(volumeKey);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['block_index'] = Variable<int>(blockIndex);
    map['block_char'] = Variable<int>(blockChar);
    if (!nullToAbsent || chapterPath != null) {
      map['chapter_path'] = Variable<String>(chapterPath);
    }
    map['chapter_count'] = Variable<int>(chapterCount);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    map['end_reached'] = Variable<bool>(endReached);
    if (!nullToAbsent || volumeJson != null) {
      map['volume_json'] = Variable<String>(volumeJson);
    }
    map['hidden'] = Variable<bool>(hidden);
    if (!nullToAbsent || hiddenAt != null) {
      map['hidden_at'] = Variable<String>(hiddenAt);
    }
    if (!nullToAbsent || ttsResume != null) {
      map['tts_resume'] = Variable<String>(ttsResume);
    }
    return map;
  }

  ReadingProgressRowsCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressRowsCompanion(
      volumeKey: Value(volumeKey),
      chapterIndex: Value(chapterIndex),
      blockIndex: Value(blockIndex),
      blockChar: Value(blockChar),
      chapterPath: chapterPath == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterPath),
      chapterCount: Value(chapterCount),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      endReached: Value(endReached),
      volumeJson: volumeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(volumeJson),
      hidden: Value(hidden),
      hiddenAt: hiddenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hiddenAt),
      ttsResume: ttsResume == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsResume),
    );
  }

  factory ReadingProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressRow(
      volumeKey: serializer.fromJson<String>(json['volumeKey']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      blockIndex: serializer.fromJson<int>(json['blockIndex']),
      blockChar: serializer.fromJson<int>(json['blockChar']),
      chapterPath: serializer.fromJson<String?>(json['chapterPath']),
      chapterCount: serializer.fromJson<int>(json['chapterCount']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
      endReached: serializer.fromJson<bool>(json['endReached']),
      volumeJson: serializer.fromJson<String?>(json['volumeJson']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      hiddenAt: serializer.fromJson<String?>(json['hiddenAt']),
      ttsResume: serializer.fromJson<String?>(json['ttsResume']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'volumeKey': serializer.toJson<String>(volumeKey),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'blockIndex': serializer.toJson<int>(blockIndex),
      'blockChar': serializer.toJson<int>(blockChar),
      'chapterPath': serializer.toJson<String?>(chapterPath),
      'chapterCount': serializer.toJson<int>(chapterCount),
      'updatedAt': serializer.toJson<String?>(updatedAt),
      'endReached': serializer.toJson<bool>(endReached),
      'volumeJson': serializer.toJson<String?>(volumeJson),
      'hidden': serializer.toJson<bool>(hidden),
      'hiddenAt': serializer.toJson<String?>(hiddenAt),
      'ttsResume': serializer.toJson<String?>(ttsResume),
    };
  }

  ReadingProgressRow copyWith({
    String? volumeKey,
    int? chapterIndex,
    int? blockIndex,
    int? blockChar,
    Value<String?> chapterPath = const Value.absent(),
    int? chapterCount,
    Value<String?> updatedAt = const Value.absent(),
    bool? endReached,
    Value<String?> volumeJson = const Value.absent(),
    bool? hidden,
    Value<String?> hiddenAt = const Value.absent(),
    Value<String?> ttsResume = const Value.absent(),
  }) => ReadingProgressRow(
    volumeKey: volumeKey ?? this.volumeKey,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    blockIndex: blockIndex ?? this.blockIndex,
    blockChar: blockChar ?? this.blockChar,
    chapterPath: chapterPath.present ? chapterPath.value : this.chapterPath,
    chapterCount: chapterCount ?? this.chapterCount,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    endReached: endReached ?? this.endReached,
    volumeJson: volumeJson.present ? volumeJson.value : this.volumeJson,
    hidden: hidden ?? this.hidden,
    hiddenAt: hiddenAt.present ? hiddenAt.value : this.hiddenAt,
    ttsResume: ttsResume.present ? ttsResume.value : this.ttsResume,
  );
  ReadingProgressRow copyWithCompanion(ReadingProgressRowsCompanion data) {
    return ReadingProgressRow(
      volumeKey: data.volumeKey.present ? data.volumeKey.value : this.volumeKey,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      blockIndex: data.blockIndex.present
          ? data.blockIndex.value
          : this.blockIndex,
      blockChar: data.blockChar.present ? data.blockChar.value : this.blockChar,
      chapterPath: data.chapterPath.present
          ? data.chapterPath.value
          : this.chapterPath,
      chapterCount: data.chapterCount.present
          ? data.chapterCount.value
          : this.chapterCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      endReached: data.endReached.present
          ? data.endReached.value
          : this.endReached,
      volumeJson: data.volumeJson.present
          ? data.volumeJson.value
          : this.volumeJson,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      hiddenAt: data.hiddenAt.present ? data.hiddenAt.value : this.hiddenAt,
      ttsResume: data.ttsResume.present ? data.ttsResume.value : this.ttsResume,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRow(')
          ..write('volumeKey: $volumeKey, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('blockChar: $blockChar, ')
          ..write('chapterPath: $chapterPath, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('endReached: $endReached, ')
          ..write('volumeJson: $volumeJson, ')
          ..write('hidden: $hidden, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('ttsResume: $ttsResume')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    volumeKey,
    chapterIndex,
    blockIndex,
    blockChar,
    chapterPath,
    chapterCount,
    updatedAt,
    endReached,
    volumeJson,
    hidden,
    hiddenAt,
    ttsResume,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressRow &&
          other.volumeKey == this.volumeKey &&
          other.chapterIndex == this.chapterIndex &&
          other.blockIndex == this.blockIndex &&
          other.blockChar == this.blockChar &&
          other.chapterPath == this.chapterPath &&
          other.chapterCount == this.chapterCount &&
          other.updatedAt == this.updatedAt &&
          other.endReached == this.endReached &&
          other.volumeJson == this.volumeJson &&
          other.hidden == this.hidden &&
          other.hiddenAt == this.hiddenAt &&
          other.ttsResume == this.ttsResume);
}

class ReadingProgressRowsCompanion extends UpdateCompanion<ReadingProgressRow> {
  final Value<String> volumeKey;
  final Value<int> chapterIndex;
  final Value<int> blockIndex;
  final Value<int> blockChar;
  final Value<String?> chapterPath;
  final Value<int> chapterCount;
  final Value<String?> updatedAt;
  final Value<bool> endReached;
  final Value<String?> volumeJson;
  final Value<bool> hidden;
  final Value<String?> hiddenAt;
  final Value<String?> ttsResume;
  final Value<int> rowid;
  const ReadingProgressRowsCompanion({
    this.volumeKey = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.blockIndex = const Value.absent(),
    this.blockChar = const Value.absent(),
    this.chapterPath = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.endReached = const Value.absent(),
    this.volumeJson = const Value.absent(),
    this.hidden = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.ttsResume = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressRowsCompanion.insert({
    required String volumeKey,
    this.chapterIndex = const Value.absent(),
    this.blockIndex = const Value.absent(),
    this.blockChar = const Value.absent(),
    this.chapterPath = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.endReached = const Value.absent(),
    this.volumeJson = const Value.absent(),
    this.hidden = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.ttsResume = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : volumeKey = Value(volumeKey);
  static Insertable<ReadingProgressRow> custom({
    Expression<String>? volumeKey,
    Expression<int>? chapterIndex,
    Expression<int>? blockIndex,
    Expression<int>? blockChar,
    Expression<String>? chapterPath,
    Expression<int>? chapterCount,
    Expression<String>? updatedAt,
    Expression<bool>? endReached,
    Expression<String>? volumeJson,
    Expression<bool>? hidden,
    Expression<String>? hiddenAt,
    Expression<String>? ttsResume,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (volumeKey != null) 'volume_key': volumeKey,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (blockIndex != null) 'block_index': blockIndex,
      if (blockChar != null) 'block_char': blockChar,
      if (chapterPath != null) 'chapter_path': chapterPath,
      if (chapterCount != null) 'chapter_count': chapterCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (endReached != null) 'end_reached': endReached,
      if (volumeJson != null) 'volume_json': volumeJson,
      if (hidden != null) 'hidden': hidden,
      if (hiddenAt != null) 'hidden_at': hiddenAt,
      if (ttsResume != null) 'tts_resume': ttsResume,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressRowsCompanion copyWith({
    Value<String>? volumeKey,
    Value<int>? chapterIndex,
    Value<int>? blockIndex,
    Value<int>? blockChar,
    Value<String?>? chapterPath,
    Value<int>? chapterCount,
    Value<String?>? updatedAt,
    Value<bool>? endReached,
    Value<String?>? volumeJson,
    Value<bool>? hidden,
    Value<String?>? hiddenAt,
    Value<String?>? ttsResume,
    Value<int>? rowid,
  }) {
    return ReadingProgressRowsCompanion(
      volumeKey: volumeKey ?? this.volumeKey,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      blockIndex: blockIndex ?? this.blockIndex,
      blockChar: blockChar ?? this.blockChar,
      chapterPath: chapterPath ?? this.chapterPath,
      chapterCount: chapterCount ?? this.chapterCount,
      updatedAt: updatedAt ?? this.updatedAt,
      endReached: endReached ?? this.endReached,
      volumeJson: volumeJson ?? this.volumeJson,
      hidden: hidden ?? this.hidden,
      hiddenAt: hiddenAt ?? this.hiddenAt,
      ttsResume: ttsResume ?? this.ttsResume,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (volumeKey.present) {
      map['volume_key'] = Variable<String>(volumeKey.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (blockIndex.present) {
      map['block_index'] = Variable<int>(blockIndex.value);
    }
    if (blockChar.present) {
      map['block_char'] = Variable<int>(blockChar.value);
    }
    if (chapterPath.present) {
      map['chapter_path'] = Variable<String>(chapterPath.value);
    }
    if (chapterCount.present) {
      map['chapter_count'] = Variable<int>(chapterCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (endReached.present) {
      map['end_reached'] = Variable<bool>(endReached.value);
    }
    if (volumeJson.present) {
      map['volume_json'] = Variable<String>(volumeJson.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (hiddenAt.present) {
      map['hidden_at'] = Variable<String>(hiddenAt.value);
    }
    if (ttsResume.present) {
      map['tts_resume'] = Variable<String>(ttsResume.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRowsCompanion(')
          ..write('volumeKey: $volumeKey, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('blockChar: $blockChar, ')
          ..write('chapterPath: $chapterPath, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('endReached: $endReached, ')
          ..write('volumeJson: $volumeJson, ')
          ..write('hidden: $hidden, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('ttsResume: $ttsResume, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarkRowsTable extends BookmarkRows
    with TableInfo<$BookmarkRowsTable, BookmarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarkRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _volumeKeyMeta = const VerificationMeta(
    'volumeKey',
  );
  @override
  late final GeneratedColumn<String> volumeKey = GeneratedColumn<String>(
    'volume_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookmarkIdMeta = const VerificationMeta(
    'bookmarkId',
  );
  @override
  late final GeneratedColumn<String> bookmarkId = GeneratedColumn<String>(
    'bookmark_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _blockIndexMeta = const VerificationMeta(
    'blockIndex',
  );
  @override
  late final GeneratedColumn<int> blockIndex = GeneratedColumn<int>(
    'block_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _snippetMeta = const VerificationMeta(
    'snippet',
  );
  @override
  late final GeneratedColumn<String> snippet = GeneratedColumn<String>(
    'snippet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isHighlightMeta = const VerificationMeta(
    'isHighlight',
  );
  @override
  late final GeneratedColumn<bool> isHighlight = GeneratedColumn<bool>(
    'is_highlight',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_highlight" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('yellow'),
  );
  static const VerificationMeta _startCharMeta = const VerificationMeta(
    'startChar',
  );
  @override
  late final GeneratedColumn<int> startChar = GeneratedColumn<int>(
    'start_char',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endCharMeta = const VerificationMeta(
    'endChar',
  );
  @override
  late final GeneratedColumn<int> endChar = GeneratedColumn<int>(
    'end_char',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endBlockIndexMeta = const VerificationMeta(
    'endBlockIndex',
  );
  @override
  late final GeneratedColumn<int> endBlockIndex = GeneratedColumn<int>(
    'end_block_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _selectedTextMeta = const VerificationMeta(
    'selectedText',
  );
  @override
  late final GeneratedColumn<String> selectedText = GeneratedColumn<String>(
    'selected_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    volumeKey,
    bookmarkId,
    chapterIndex,
    blockIndex,
    chapterTitle,
    snippet,
    createdAt,
    isHighlight,
    note,
    color,
    startChar,
    endChar,
    endBlockIndex,
    selectedText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmark_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookmarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('volume_key')) {
      context.handle(
        _volumeKeyMeta,
        volumeKey.isAcceptableOrUnknown(data['volume_key']!, _volumeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeKeyMeta);
    }
    if (data.containsKey('bookmark_id')) {
      context.handle(
        _bookmarkIdMeta,
        bookmarkId.isAcceptableOrUnknown(data['bookmark_id']!, _bookmarkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookmarkIdMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('block_index')) {
      context.handle(
        _blockIndexMeta,
        blockIndex.isAcceptableOrUnknown(data['block_index']!, _blockIndexMeta),
      );
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('snippet')) {
      context.handle(
        _snippetMeta,
        snippet.isAcceptableOrUnknown(data['snippet']!, _snippetMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('is_highlight')) {
      context.handle(
        _isHighlightMeta,
        isHighlight.isAcceptableOrUnknown(
          data['is_highlight']!,
          _isHighlightMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('start_char')) {
      context.handle(
        _startCharMeta,
        startChar.isAcceptableOrUnknown(data['start_char']!, _startCharMeta),
      );
    }
    if (data.containsKey('end_char')) {
      context.handle(
        _endCharMeta,
        endChar.isAcceptableOrUnknown(data['end_char']!, _endCharMeta),
      );
    }
    if (data.containsKey('end_block_index')) {
      context.handle(
        _endBlockIndexMeta,
        endBlockIndex.isAcceptableOrUnknown(
          data['end_block_index']!,
          _endBlockIndexMeta,
        ),
      );
    }
    if (data.containsKey('selected_text')) {
      context.handle(
        _selectedTextMeta,
        selectedText.isAcceptableOrUnknown(
          data['selected_text']!,
          _selectedTextMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {volumeKey, bookmarkId};
  @override
  BookmarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookmarkRow(
      volumeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_key'],
      )!,
      bookmarkId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bookmark_id'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      blockIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_index'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      )!,
      snippet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      isHighlight: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_highlight'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      startChar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_char'],
      ),
      endChar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_char'],
      ),
      endBlockIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_block_index'],
      ),
      selectedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_text'],
      )!,
    );
  }

  @override
  $BookmarkRowsTable createAlias(String alias) {
    return $BookmarkRowsTable(attachedDatabase, alias);
  }
}

class BookmarkRow extends DataClass implements Insertable<BookmarkRow> {
  /// `seriesOpdsId/fileName`, same composite key as reading progress.
  final String volumeKey;
  final String bookmarkId;
  final int chapterIndex;
  final int blockIndex;
  final String chapterTitle;
  final String snippet;
  final String createdAt;
  final bool isHighlight;
  final String note;
  final String color;

  /// Character-range highlight fields (null on legacy whole-block highlights).
  final int? startChar;
  final int? endChar;
  final int? endBlockIndex;
  final String selectedText;
  const BookmarkRow({
    required this.volumeKey,
    required this.bookmarkId,
    required this.chapterIndex,
    required this.blockIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.createdAt,
    required this.isHighlight,
    required this.note,
    required this.color,
    this.startChar,
    this.endChar,
    this.endBlockIndex,
    required this.selectedText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['volume_key'] = Variable<String>(volumeKey);
    map['bookmark_id'] = Variable<String>(bookmarkId);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['block_index'] = Variable<int>(blockIndex);
    map['chapter_title'] = Variable<String>(chapterTitle);
    map['snippet'] = Variable<String>(snippet);
    map['created_at'] = Variable<String>(createdAt);
    map['is_highlight'] = Variable<bool>(isHighlight);
    map['note'] = Variable<String>(note);
    map['color'] = Variable<String>(color);
    if (!nullToAbsent || startChar != null) {
      map['start_char'] = Variable<int>(startChar);
    }
    if (!nullToAbsent || endChar != null) {
      map['end_char'] = Variable<int>(endChar);
    }
    if (!nullToAbsent || endBlockIndex != null) {
      map['end_block_index'] = Variable<int>(endBlockIndex);
    }
    map['selected_text'] = Variable<String>(selectedText);
    return map;
  }

  BookmarkRowsCompanion toCompanion(bool nullToAbsent) {
    return BookmarkRowsCompanion(
      volumeKey: Value(volumeKey),
      bookmarkId: Value(bookmarkId),
      chapterIndex: Value(chapterIndex),
      blockIndex: Value(blockIndex),
      chapterTitle: Value(chapterTitle),
      snippet: Value(snippet),
      createdAt: Value(createdAt),
      isHighlight: Value(isHighlight),
      note: Value(note),
      color: Value(color),
      startChar: startChar == null && nullToAbsent
          ? const Value.absent()
          : Value(startChar),
      endChar: endChar == null && nullToAbsent
          ? const Value.absent()
          : Value(endChar),
      endBlockIndex: endBlockIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(endBlockIndex),
      selectedText: Value(selectedText),
    );
  }

  factory BookmarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookmarkRow(
      volumeKey: serializer.fromJson<String>(json['volumeKey']),
      bookmarkId: serializer.fromJson<String>(json['bookmarkId']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      blockIndex: serializer.fromJson<int>(json['blockIndex']),
      chapterTitle: serializer.fromJson<String>(json['chapterTitle']),
      snippet: serializer.fromJson<String>(json['snippet']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      isHighlight: serializer.fromJson<bool>(json['isHighlight']),
      note: serializer.fromJson<String>(json['note']),
      color: serializer.fromJson<String>(json['color']),
      startChar: serializer.fromJson<int?>(json['startChar']),
      endChar: serializer.fromJson<int?>(json['endChar']),
      endBlockIndex: serializer.fromJson<int?>(json['endBlockIndex']),
      selectedText: serializer.fromJson<String>(json['selectedText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'volumeKey': serializer.toJson<String>(volumeKey),
      'bookmarkId': serializer.toJson<String>(bookmarkId),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'blockIndex': serializer.toJson<int>(blockIndex),
      'chapterTitle': serializer.toJson<String>(chapterTitle),
      'snippet': serializer.toJson<String>(snippet),
      'createdAt': serializer.toJson<String>(createdAt),
      'isHighlight': serializer.toJson<bool>(isHighlight),
      'note': serializer.toJson<String>(note),
      'color': serializer.toJson<String>(color),
      'startChar': serializer.toJson<int?>(startChar),
      'endChar': serializer.toJson<int?>(endChar),
      'endBlockIndex': serializer.toJson<int?>(endBlockIndex),
      'selectedText': serializer.toJson<String>(selectedText),
    };
  }

  BookmarkRow copyWith({
    String? volumeKey,
    String? bookmarkId,
    int? chapterIndex,
    int? blockIndex,
    String? chapterTitle,
    String? snippet,
    String? createdAt,
    bool? isHighlight,
    String? note,
    String? color,
    Value<int?> startChar = const Value.absent(),
    Value<int?> endChar = const Value.absent(),
    Value<int?> endBlockIndex = const Value.absent(),
    String? selectedText,
  }) => BookmarkRow(
    volumeKey: volumeKey ?? this.volumeKey,
    bookmarkId: bookmarkId ?? this.bookmarkId,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    blockIndex: blockIndex ?? this.blockIndex,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    snippet: snippet ?? this.snippet,
    createdAt: createdAt ?? this.createdAt,
    isHighlight: isHighlight ?? this.isHighlight,
    note: note ?? this.note,
    color: color ?? this.color,
    startChar: startChar.present ? startChar.value : this.startChar,
    endChar: endChar.present ? endChar.value : this.endChar,
    endBlockIndex: endBlockIndex.present
        ? endBlockIndex.value
        : this.endBlockIndex,
    selectedText: selectedText ?? this.selectedText,
  );
  BookmarkRow copyWithCompanion(BookmarkRowsCompanion data) {
    return BookmarkRow(
      volumeKey: data.volumeKey.present ? data.volumeKey.value : this.volumeKey,
      bookmarkId: data.bookmarkId.present
          ? data.bookmarkId.value
          : this.bookmarkId,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      blockIndex: data.blockIndex.present
          ? data.blockIndex.value
          : this.blockIndex,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      snippet: data.snippet.present ? data.snippet.value : this.snippet,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isHighlight: data.isHighlight.present
          ? data.isHighlight.value
          : this.isHighlight,
      note: data.note.present ? data.note.value : this.note,
      color: data.color.present ? data.color.value : this.color,
      startChar: data.startChar.present ? data.startChar.value : this.startChar,
      endChar: data.endChar.present ? data.endChar.value : this.endChar,
      endBlockIndex: data.endBlockIndex.present
          ? data.endBlockIndex.value
          : this.endBlockIndex,
      selectedText: data.selectedText.present
          ? data.selectedText.value
          : this.selectedText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookmarkRow(')
          ..write('volumeKey: $volumeKey, ')
          ..write('bookmarkId: $bookmarkId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('snippet: $snippet, ')
          ..write('createdAt: $createdAt, ')
          ..write('isHighlight: $isHighlight, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('startChar: $startChar, ')
          ..write('endChar: $endChar, ')
          ..write('endBlockIndex: $endBlockIndex, ')
          ..write('selectedText: $selectedText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    volumeKey,
    bookmarkId,
    chapterIndex,
    blockIndex,
    chapterTitle,
    snippet,
    createdAt,
    isHighlight,
    note,
    color,
    startChar,
    endChar,
    endBlockIndex,
    selectedText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkRow &&
          other.volumeKey == this.volumeKey &&
          other.bookmarkId == this.bookmarkId &&
          other.chapterIndex == this.chapterIndex &&
          other.blockIndex == this.blockIndex &&
          other.chapterTitle == this.chapterTitle &&
          other.snippet == this.snippet &&
          other.createdAt == this.createdAt &&
          other.isHighlight == this.isHighlight &&
          other.note == this.note &&
          other.color == this.color &&
          other.startChar == this.startChar &&
          other.endChar == this.endChar &&
          other.endBlockIndex == this.endBlockIndex &&
          other.selectedText == this.selectedText);
}

class BookmarkRowsCompanion extends UpdateCompanion<BookmarkRow> {
  final Value<String> volumeKey;
  final Value<String> bookmarkId;
  final Value<int> chapterIndex;
  final Value<int> blockIndex;
  final Value<String> chapterTitle;
  final Value<String> snippet;
  final Value<String> createdAt;
  final Value<bool> isHighlight;
  final Value<String> note;
  final Value<String> color;
  final Value<int?> startChar;
  final Value<int?> endChar;
  final Value<int?> endBlockIndex;
  final Value<String> selectedText;
  final Value<int> rowid;
  const BookmarkRowsCompanion({
    this.volumeKey = const Value.absent(),
    this.bookmarkId = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.blockIndex = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.snippet = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isHighlight = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.startChar = const Value.absent(),
    this.endChar = const Value.absent(),
    this.endBlockIndex = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarkRowsCompanion.insert({
    required String volumeKey,
    required String bookmarkId,
    this.chapterIndex = const Value.absent(),
    this.blockIndex = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.snippet = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isHighlight = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.startChar = const Value.absent(),
    this.endChar = const Value.absent(),
    this.endBlockIndex = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : volumeKey = Value(volumeKey),
       bookmarkId = Value(bookmarkId);
  static Insertable<BookmarkRow> custom({
    Expression<String>? volumeKey,
    Expression<String>? bookmarkId,
    Expression<int>? chapterIndex,
    Expression<int>? blockIndex,
    Expression<String>? chapterTitle,
    Expression<String>? snippet,
    Expression<String>? createdAt,
    Expression<bool>? isHighlight,
    Expression<String>? note,
    Expression<String>? color,
    Expression<int>? startChar,
    Expression<int>? endChar,
    Expression<int>? endBlockIndex,
    Expression<String>? selectedText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (volumeKey != null) 'volume_key': volumeKey,
      if (bookmarkId != null) 'bookmark_id': bookmarkId,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (blockIndex != null) 'block_index': blockIndex,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (snippet != null) 'snippet': snippet,
      if (createdAt != null) 'created_at': createdAt,
      if (isHighlight != null) 'is_highlight': isHighlight,
      if (note != null) 'note': note,
      if (color != null) 'color': color,
      if (startChar != null) 'start_char': startChar,
      if (endChar != null) 'end_char': endChar,
      if (endBlockIndex != null) 'end_block_index': endBlockIndex,
      if (selectedText != null) 'selected_text': selectedText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarkRowsCompanion copyWith({
    Value<String>? volumeKey,
    Value<String>? bookmarkId,
    Value<int>? chapterIndex,
    Value<int>? blockIndex,
    Value<String>? chapterTitle,
    Value<String>? snippet,
    Value<String>? createdAt,
    Value<bool>? isHighlight,
    Value<String>? note,
    Value<String>? color,
    Value<int?>? startChar,
    Value<int?>? endChar,
    Value<int?>? endBlockIndex,
    Value<String>? selectedText,
    Value<int>? rowid,
  }) {
    return BookmarkRowsCompanion(
      volumeKey: volumeKey ?? this.volumeKey,
      bookmarkId: bookmarkId ?? this.bookmarkId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      blockIndex: blockIndex ?? this.blockIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      snippet: snippet ?? this.snippet,
      createdAt: createdAt ?? this.createdAt,
      isHighlight: isHighlight ?? this.isHighlight,
      note: note ?? this.note,
      color: color ?? this.color,
      startChar: startChar ?? this.startChar,
      endChar: endChar ?? this.endChar,
      endBlockIndex: endBlockIndex ?? this.endBlockIndex,
      selectedText: selectedText ?? this.selectedText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (volumeKey.present) {
      map['volume_key'] = Variable<String>(volumeKey.value);
    }
    if (bookmarkId.present) {
      map['bookmark_id'] = Variable<String>(bookmarkId.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (blockIndex.present) {
      map['block_index'] = Variable<int>(blockIndex.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (snippet.present) {
      map['snippet'] = Variable<String>(snippet.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (isHighlight.present) {
      map['is_highlight'] = Variable<bool>(isHighlight.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (startChar.present) {
      map['start_char'] = Variable<int>(startChar.value);
    }
    if (endChar.present) {
      map['end_char'] = Variable<int>(endChar.value);
    }
    if (endBlockIndex.present) {
      map['end_block_index'] = Variable<int>(endBlockIndex.value);
    }
    if (selectedText.present) {
      map['selected_text'] = Variable<String>(selectedText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarkRowsCompanion(')
          ..write('volumeKey: $volumeKey, ')
          ..write('bookmarkId: $bookmarkId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('snippet: $snippet, ')
          ..write('createdAt: $createdAt, ')
          ..write('isHighlight: $isHighlight, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('startChar: $startChar, ')
          ..write('endChar: $endChar, ')
          ..write('endBlockIndex: $endBlockIndex, ')
          ..write('selectedText: $selectedText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionRowsTable extends CollectionRows
    with TableInfo<$CollectionRowsTable, CollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdsJsonMeta = const VerificationMeta(
    'seriesIdsJson',
  );
  @override
  late final GeneratedColumn<String> seriesIdsJson = GeneratedColumn<String>(
    'series_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, seriesIdsJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('series_ids_json')) {
      context.handle(
        _seriesIdsJsonMeta,
        seriesIdsJson.isAcceptableOrUnknown(
          data['series_ids_json']!,
          _seriesIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      seriesIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_ids_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CollectionRowsTable createAlias(String alias) {
    return $CollectionRowsTable(attachedDatabase, alias);
  }
}

class CollectionRow extends DataClass implements Insertable<CollectionRow> {
  final String id;
  final String name;
  final String seriesIdsJson;
  final String createdAt;
  const CollectionRow({
    required this.id,
    required this.name,
    required this.seriesIdsJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['series_ids_json'] = Variable<String>(seriesIdsJson);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  CollectionRowsCompanion toCompanion(bool nullToAbsent) {
    return CollectionRowsCompanion(
      id: Value(id),
      name: Value(name),
      seriesIdsJson: Value(seriesIdsJson),
      createdAt: Value(createdAt),
    );
  }

  factory CollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      seriesIdsJson: serializer.fromJson<String>(json['seriesIdsJson']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'seriesIdsJson': serializer.toJson<String>(seriesIdsJson),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  CollectionRow copyWith({
    String? id,
    String? name,
    String? seriesIdsJson,
    String? createdAt,
  }) => CollectionRow(
    id: id ?? this.id,
    name: name ?? this.name,
    seriesIdsJson: seriesIdsJson ?? this.seriesIdsJson,
    createdAt: createdAt ?? this.createdAt,
  );
  CollectionRow copyWithCompanion(CollectionRowsCompanion data) {
    return CollectionRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      seriesIdsJson: data.seriesIdsJson.present
          ? data.seriesIdsJson.value
          : this.seriesIdsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('seriesIdsJson: $seriesIdsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, seriesIdsJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.seriesIdsJson == this.seriesIdsJson &&
          other.createdAt == this.createdAt);
}

class CollectionRowsCompanion extends UpdateCompanion<CollectionRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> seriesIdsJson;
  final Value<String> createdAt;
  final Value<int> rowid;
  const CollectionRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.seriesIdsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionRowsCompanion.insert({
    required String id,
    required String name,
    this.seriesIdsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<CollectionRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? seriesIdsJson,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (seriesIdsJson != null) 'series_ids_json': seriesIdsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? seriesIdsJson,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return CollectionRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      seriesIdsJson: seriesIdsJson ?? this.seriesIdsJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (seriesIdsJson.present) {
      map['series_ids_json'] = Variable<String>(seriesIdsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('seriesIdsJson: $seriesIdsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyActivityRowsTable extends DailyActivityRows
    with TableInfo<$DailyActivityRowsTable, DailyActivityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyActivityRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secondsMeta = const VerificationMeta(
    'seconds',
  );
  @override
  late final GeneratedColumn<int> seconds = GeneratedColumn<int>(
    'seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wordsMeta = const VerificationMeta('words');
  @override
  late final GeneratedColumn<int> words = GeneratedColumn<int>(
    'words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [day, seconds, words];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_activity_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyActivityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('seconds')) {
      context.handle(
        _secondsMeta,
        seconds.isAcceptableOrUnknown(data['seconds']!, _secondsMeta),
      );
    }
    if (data.containsKey('words')) {
      context.handle(
        _wordsMeta,
        words.isAcceptableOrUnknown(data['words']!, _wordsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  DailyActivityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyActivityRow(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      seconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seconds'],
      )!,
      words: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}words'],
      )!,
    );
  }

  @override
  $DailyActivityRowsTable createAlias(String alias) {
    return $DailyActivityRowsTable(attachedDatabase, alias);
  }
}

class DailyActivityRow extends DataClass
    implements Insertable<DailyActivityRow> {
  final String day;
  final int seconds;

  /// New words read that day — forward progress only, so re-reading never
  /// inflates the tally. Drives reading-pace and TTS-cost estimates.
  final int words;
  const DailyActivityRow({
    required this.day,
    required this.seconds,
    required this.words,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['seconds'] = Variable<int>(seconds);
    map['words'] = Variable<int>(words);
    return map;
  }

  DailyActivityRowsCompanion toCompanion(bool nullToAbsent) {
    return DailyActivityRowsCompanion(
      day: Value(day),
      seconds: Value(seconds),
      words: Value(words),
    );
  }

  factory DailyActivityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyActivityRow(
      day: serializer.fromJson<String>(json['day']),
      seconds: serializer.fromJson<int>(json['seconds']),
      words: serializer.fromJson<int>(json['words']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'seconds': serializer.toJson<int>(seconds),
      'words': serializer.toJson<int>(words),
    };
  }

  DailyActivityRow copyWith({String? day, int? seconds, int? words}) =>
      DailyActivityRow(
        day: day ?? this.day,
        seconds: seconds ?? this.seconds,
        words: words ?? this.words,
      );
  DailyActivityRow copyWithCompanion(DailyActivityRowsCompanion data) {
    return DailyActivityRow(
      day: data.day.present ? data.day.value : this.day,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
      words: data.words.present ? data.words.value : this.words,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyActivityRow(')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('words: $words')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, seconds, words);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyActivityRow &&
          other.day == this.day &&
          other.seconds == this.seconds &&
          other.words == this.words);
}

class DailyActivityRowsCompanion extends UpdateCompanion<DailyActivityRow> {
  final Value<String> day;
  final Value<int> seconds;
  final Value<int> words;
  final Value<int> rowid;
  const DailyActivityRowsCompanion({
    this.day = const Value.absent(),
    this.seconds = const Value.absent(),
    this.words = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyActivityRowsCompanion.insert({
    required String day,
    this.seconds = const Value.absent(),
    this.words = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : day = Value(day);
  static Insertable<DailyActivityRow> custom({
    Expression<String>? day,
    Expression<int>? seconds,
    Expression<int>? words,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (seconds != null) 'seconds': seconds,
      if (words != null) 'words': words,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyActivityRowsCompanion copyWith({
    Value<String>? day,
    Value<int>? seconds,
    Value<int>? words,
    Value<int>? rowid,
  }) {
    return DailyActivityRowsCompanion(
      day: day ?? this.day,
      seconds: seconds ?? this.seconds,
      words: words ?? this.words,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (seconds.present) {
      map['seconds'] = Variable<int>(seconds.value);
    }
    if (words.present) {
      map['words'] = Variable<int>(words.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyActivityRowsCompanion(')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('words: $words, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VolumeActivityRowsTable extends VolumeActivityRows
    with TableInfo<$VolumeActivityRowsTable, VolumeActivityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VolumeActivityRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _volumeKeyMeta = const VerificationMeta(
    'volumeKey',
  );
  @override
  late final GeneratedColumn<String> volumeKey = GeneratedColumn<String>(
    'volume_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secondsMeta = const VerificationMeta(
    'seconds',
  );
  @override
  late final GeneratedColumn<int> seconds = GeneratedColumn<int>(
    'seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wordsMeta = const VerificationMeta('words');
  @override
  late final GeneratedColumn<int> words = GeneratedColumn<int>(
    'words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [volumeKey, seconds, words];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'volume_activity_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<VolumeActivityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('volume_key')) {
      context.handle(
        _volumeKeyMeta,
        volumeKey.isAcceptableOrUnknown(data['volume_key']!, _volumeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeKeyMeta);
    }
    if (data.containsKey('seconds')) {
      context.handle(
        _secondsMeta,
        seconds.isAcceptableOrUnknown(data['seconds']!, _secondsMeta),
      );
    }
    if (data.containsKey('words')) {
      context.handle(
        _wordsMeta,
        words.isAcceptableOrUnknown(data['words']!, _wordsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {volumeKey};
  @override
  VolumeActivityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VolumeActivityRow(
      volumeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_key'],
      )!,
      seconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seconds'],
      )!,
      words: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}words'],
      )!,
    );
  }

  @override
  $VolumeActivityRowsTable createAlias(String alias) {
    return $VolumeActivityRowsTable(attachedDatabase, alias);
  }
}

class VolumeActivityRow extends DataClass
    implements Insertable<VolumeActivityRow> {
  final String volumeKey;
  final int seconds;

  /// High-water mark of words read in this volume — the ceiling that keeps
  /// re-reads from double-counting into the daily tally.
  final int words;
  const VolumeActivityRow({
    required this.volumeKey,
    required this.seconds,
    required this.words,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['volume_key'] = Variable<String>(volumeKey);
    map['seconds'] = Variable<int>(seconds);
    map['words'] = Variable<int>(words);
    return map;
  }

  VolumeActivityRowsCompanion toCompanion(bool nullToAbsent) {
    return VolumeActivityRowsCompanion(
      volumeKey: Value(volumeKey),
      seconds: Value(seconds),
      words: Value(words),
    );
  }

  factory VolumeActivityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VolumeActivityRow(
      volumeKey: serializer.fromJson<String>(json['volumeKey']),
      seconds: serializer.fromJson<int>(json['seconds']),
      words: serializer.fromJson<int>(json['words']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'volumeKey': serializer.toJson<String>(volumeKey),
      'seconds': serializer.toJson<int>(seconds),
      'words': serializer.toJson<int>(words),
    };
  }

  VolumeActivityRow copyWith({String? volumeKey, int? seconds, int? words}) =>
      VolumeActivityRow(
        volumeKey: volumeKey ?? this.volumeKey,
        seconds: seconds ?? this.seconds,
        words: words ?? this.words,
      );
  VolumeActivityRow copyWithCompanion(VolumeActivityRowsCompanion data) {
    return VolumeActivityRow(
      volumeKey: data.volumeKey.present ? data.volumeKey.value : this.volumeKey,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
      words: data.words.present ? data.words.value : this.words,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VolumeActivityRow(')
          ..write('volumeKey: $volumeKey, ')
          ..write('seconds: $seconds, ')
          ..write('words: $words')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(volumeKey, seconds, words);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VolumeActivityRow &&
          other.volumeKey == this.volumeKey &&
          other.seconds == this.seconds &&
          other.words == this.words);
}

class VolumeActivityRowsCompanion extends UpdateCompanion<VolumeActivityRow> {
  final Value<String> volumeKey;
  final Value<int> seconds;
  final Value<int> words;
  final Value<int> rowid;
  const VolumeActivityRowsCompanion({
    this.volumeKey = const Value.absent(),
    this.seconds = const Value.absent(),
    this.words = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VolumeActivityRowsCompanion.insert({
    required String volumeKey,
    this.seconds = const Value.absent(),
    this.words = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : volumeKey = Value(volumeKey);
  static Insertable<VolumeActivityRow> custom({
    Expression<String>? volumeKey,
    Expression<int>? seconds,
    Expression<int>? words,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (volumeKey != null) 'volume_key': volumeKey,
      if (seconds != null) 'seconds': seconds,
      if (words != null) 'words': words,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VolumeActivityRowsCompanion copyWith({
    Value<String>? volumeKey,
    Value<int>? seconds,
    Value<int>? words,
    Value<int>? rowid,
  }) {
    return VolumeActivityRowsCompanion(
      volumeKey: volumeKey ?? this.volumeKey,
      seconds: seconds ?? this.seconds,
      words: words ?? this.words,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (volumeKey.present) {
      map['volume_key'] = Variable<String>(volumeKey.value);
    }
    if (seconds.present) {
      map['seconds'] = Variable<int>(seconds.value);
    }
    if (words.present) {
      map['words'] = Variable<int>(words.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VolumeActivityRowsCompanion(')
          ..write('volumeKey: $volumeKey, ')
          ..write('seconds: $seconds, ')
          ..write('words: $words, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecOutcomeRowsTable extends RecOutcomeRows
    with TableInfo<$RecOutcomeRowsTable, RecOutcomeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecOutcomeRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _impressionsMeta = const VerificationMeta(
    'impressions',
  );
  @override
  late final GeneratedColumn<int> impressions = GeneratedColumn<int>(
    'impressions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tapsMeta = const VerificationMeta('taps');
  @override
  late final GeneratedColumn<int> taps = GeneratedColumn<int>(
    'taps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastShownDayMeta = const VerificationMeta(
    'lastShownDay',
  );
  @override
  late final GeneratedColumn<String> lastShownDay = GeneratedColumn<String>(
    'last_shown_day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lastTapAtMeta = const VerificationMeta(
    'lastTapAt',
  );
  @override
  late final GeneratedColumn<String> lastTapAt = GeneratedColumn<String>(
    'last_tap_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    impressions,
    taps,
    lastShownDay,
    lastTapAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rec_outcome_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecOutcomeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('impressions')) {
      context.handle(
        _impressionsMeta,
        impressions.isAcceptableOrUnknown(
          data['impressions']!,
          _impressionsMeta,
        ),
      );
    }
    if (data.containsKey('taps')) {
      context.handle(
        _tapsMeta,
        taps.isAcceptableOrUnknown(data['taps']!, _tapsMeta),
      );
    }
    if (data.containsKey('last_shown_day')) {
      context.handle(
        _lastShownDayMeta,
        lastShownDay.isAcceptableOrUnknown(
          data['last_shown_day']!,
          _lastShownDayMeta,
        ),
      );
    }
    if (data.containsKey('last_tap_at')) {
      context.handle(
        _lastTapAtMeta,
        lastTapAt.isAcceptableOrUnknown(data['last_tap_at']!, _lastTapAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId};
  @override
  RecOutcomeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecOutcomeRow(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      impressions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}impressions'],
      )!,
      taps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taps'],
      )!,
      lastShownDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_shown_day'],
      )!,
      lastTapAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_tap_at'],
      ),
    );
  }

  @override
  $RecOutcomeRowsTable createAlias(String alias) {
    return $RecOutcomeRowsTable(attachedDatabase, alias);
  }
}

class RecOutcomeRow extends DataClass implements Insertable<RecOutcomeRow> {
  final int seriesId;
  final int impressions;
  final int taps;

  /// Local `YYYY-MM-DD` of the last counted impression — impressions count
  /// at most once per series per day so one busy session can't spam the
  /// counter.
  final String lastShownDay;
  final String? lastTapAt;
  const RecOutcomeRow({
    required this.seriesId,
    required this.impressions,
    required this.taps,
    required this.lastShownDay,
    this.lastTapAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<int>(seriesId);
    map['impressions'] = Variable<int>(impressions);
    map['taps'] = Variable<int>(taps);
    map['last_shown_day'] = Variable<String>(lastShownDay);
    if (!nullToAbsent || lastTapAt != null) {
      map['last_tap_at'] = Variable<String>(lastTapAt);
    }
    return map;
  }

  RecOutcomeRowsCompanion toCompanion(bool nullToAbsent) {
    return RecOutcomeRowsCompanion(
      seriesId: Value(seriesId),
      impressions: Value(impressions),
      taps: Value(taps),
      lastShownDay: Value(lastShownDay),
      lastTapAt: lastTapAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastTapAt),
    );
  }

  factory RecOutcomeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecOutcomeRow(
      seriesId: serializer.fromJson<int>(json['seriesId']),
      impressions: serializer.fromJson<int>(json['impressions']),
      taps: serializer.fromJson<int>(json['taps']),
      lastShownDay: serializer.fromJson<String>(json['lastShownDay']),
      lastTapAt: serializer.fromJson<String?>(json['lastTapAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<int>(seriesId),
      'impressions': serializer.toJson<int>(impressions),
      'taps': serializer.toJson<int>(taps),
      'lastShownDay': serializer.toJson<String>(lastShownDay),
      'lastTapAt': serializer.toJson<String?>(lastTapAt),
    };
  }

  RecOutcomeRow copyWith({
    int? seriesId,
    int? impressions,
    int? taps,
    String? lastShownDay,
    Value<String?> lastTapAt = const Value.absent(),
  }) => RecOutcomeRow(
    seriesId: seriesId ?? this.seriesId,
    impressions: impressions ?? this.impressions,
    taps: taps ?? this.taps,
    lastShownDay: lastShownDay ?? this.lastShownDay,
    lastTapAt: lastTapAt.present ? lastTapAt.value : this.lastTapAt,
  );
  RecOutcomeRow copyWithCompanion(RecOutcomeRowsCompanion data) {
    return RecOutcomeRow(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      impressions: data.impressions.present
          ? data.impressions.value
          : this.impressions,
      taps: data.taps.present ? data.taps.value : this.taps,
      lastShownDay: data.lastShownDay.present
          ? data.lastShownDay.value
          : this.lastShownDay,
      lastTapAt: data.lastTapAt.present ? data.lastTapAt.value : this.lastTapAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecOutcomeRow(')
          ..write('seriesId: $seriesId, ')
          ..write('impressions: $impressions, ')
          ..write('taps: $taps, ')
          ..write('lastShownDay: $lastShownDay, ')
          ..write('lastTapAt: $lastTapAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seriesId, impressions, taps, lastShownDay, lastTapAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecOutcomeRow &&
          other.seriesId == this.seriesId &&
          other.impressions == this.impressions &&
          other.taps == this.taps &&
          other.lastShownDay == this.lastShownDay &&
          other.lastTapAt == this.lastTapAt);
}

class RecOutcomeRowsCompanion extends UpdateCompanion<RecOutcomeRow> {
  final Value<int> seriesId;
  final Value<int> impressions;
  final Value<int> taps;
  final Value<String> lastShownDay;
  final Value<String?> lastTapAt;
  const RecOutcomeRowsCompanion({
    this.seriesId = const Value.absent(),
    this.impressions = const Value.absent(),
    this.taps = const Value.absent(),
    this.lastShownDay = const Value.absent(),
    this.lastTapAt = const Value.absent(),
  });
  RecOutcomeRowsCompanion.insert({
    this.seriesId = const Value.absent(),
    this.impressions = const Value.absent(),
    this.taps = const Value.absent(),
    this.lastShownDay = const Value.absent(),
    this.lastTapAt = const Value.absent(),
  });
  static Insertable<RecOutcomeRow> custom({
    Expression<int>? seriesId,
    Expression<int>? impressions,
    Expression<int>? taps,
    Expression<String>? lastShownDay,
    Expression<String>? lastTapAt,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (impressions != null) 'impressions': impressions,
      if (taps != null) 'taps': taps,
      if (lastShownDay != null) 'last_shown_day': lastShownDay,
      if (lastTapAt != null) 'last_tap_at': lastTapAt,
    });
  }

  RecOutcomeRowsCompanion copyWith({
    Value<int>? seriesId,
    Value<int>? impressions,
    Value<int>? taps,
    Value<String>? lastShownDay,
    Value<String?>? lastTapAt,
  }) {
    return RecOutcomeRowsCompanion(
      seriesId: seriesId ?? this.seriesId,
      impressions: impressions ?? this.impressions,
      taps: taps ?? this.taps,
      lastShownDay: lastShownDay ?? this.lastShownDay,
      lastTapAt: lastTapAt ?? this.lastTapAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (impressions.present) {
      map['impressions'] = Variable<int>(impressions.value);
    }
    if (taps.present) {
      map['taps'] = Variable<int>(taps.value);
    }
    if (lastShownDay.present) {
      map['last_shown_day'] = Variable<String>(lastShownDay.value);
    }
    if (lastTapAt.present) {
      map['last_tap_at'] = Variable<String>(lastTapAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecOutcomeRowsCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('impressions: $impressions, ')
          ..write('taps: $taps, ')
          ..write('lastShownDay: $lastShownDay, ')
          ..write('lastTapAt: $lastTapAt')
          ..write(')'))
        .toString();
  }
}

class $WebSeriesRowsTable extends WebSeriesRows
    with TableInfo<$WebSeriesRowsTable, WebSeriesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WebSeriesRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastChapterUrlMeta = const VerificationMeta(
    'lastChapterUrl',
  );
  @override
  late final GeneratedColumn<String> lastChapterUrl = GeneratedColumn<String>(
    'last_chapter_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPanelMeta = const VerificationMeta(
    'lastPanel',
  );
  @override
  late final GeneratedColumn<int> lastPanel = GeneratedColumn<int>(
    'last_panel',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _latestChapterMeta = const VerificationMeta(
    'latestChapter',
  );
  @override
  late final GeneratedColumn<double> latestChapter = GeneratedColumn<double>(
    'latest_chapter',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readChapterMeta = const VerificationMeta(
    'readChapter',
  );
  @override
  late final GeneratedColumn<double> readChapter = GeneratedColumn<double>(
    'read_chapter',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<String> checkedAt = GeneratedColumn<String>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<String> openedAt = GeneratedColumn<String>(
    'opened_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<String> addedAt = GeneratedColumn<String>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    url,
    title,
    coverUrl,
    lastChapterUrl,
    lastPanel,
    latestChapter,
    readChapter,
    checkedAt,
    openedAt,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'web_series_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<WebSeriesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('last_chapter_url')) {
      context.handle(
        _lastChapterUrlMeta,
        lastChapterUrl.isAcceptableOrUnknown(
          data['last_chapter_url']!,
          _lastChapterUrlMeta,
        ),
      );
    }
    if (data.containsKey('last_panel')) {
      context.handle(
        _lastPanelMeta,
        lastPanel.isAcceptableOrUnknown(data['last_panel']!, _lastPanelMeta),
      );
    }
    if (data.containsKey('latest_chapter')) {
      context.handle(
        _latestChapterMeta,
        latestChapter.isAcceptableOrUnknown(
          data['latest_chapter']!,
          _latestChapterMeta,
        ),
      );
    }
    if (data.containsKey('read_chapter')) {
      context.handle(
        _readChapterMeta,
        readChapter.isAcceptableOrUnknown(
          data['read_chapter']!,
          _readChapterMeta,
        ),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  WebSeriesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WebSeriesRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      lastChapterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_chapter_url'],
      ),
      lastPanel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_panel'],
      )!,
      latestChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latest_chapter'],
      ),
      readChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}read_chapter'],
      ),
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_at'],
      ),
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opened_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $WebSeriesRowsTable createAlias(String alias) {
    return $WebSeriesRowsTable(attachedDatabase, alias);
  }
}

class WebSeriesRow extends DataClass implements Insertable<WebSeriesRow> {
  /// The series page's URL, which is also its identity. Not a slug: these
  /// sites hash their slugs (`rankers-return-c6f3k3os`), so the URL is the
  /// only stable name there is.
  final String url;
  final String title;
  final String? coverUrl;

  /// The chapter page last open, so tapping the series returns to it
  /// rather than to the series' front page.
  final String? lastChapterUrl;

  /// Whereabouts in that chapter, as an index into its images.
  ///
  /// Deliberately not a scroll offset. A chapter is dozens of lazily
  /// loaded panels, so when the page is reopened it is briefly short and
  /// a saved pixel position lands somewhere arbitrary. A panel is a thing
  /// that still exists once the page has settled.
  final int lastPanel;

  /// Highest chapter number the series page offered at the last check, and
  /// the highest actually opened. The pair is what makes a "new chapters"
  /// badge possible without downloading anything.
  final double? latestChapter;
  final double? readChapter;

  /// ISO-8601, like every other timestamp in this file.
  final String? checkedAt;
  final String? openedAt;
  final String addedAt;
  const WebSeriesRow({
    required this.url,
    required this.title,
    this.coverUrl,
    this.lastChapterUrl,
    required this.lastPanel,
    this.latestChapter,
    this.readChapter,
    this.checkedAt,
    this.openedAt,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || lastChapterUrl != null) {
      map['last_chapter_url'] = Variable<String>(lastChapterUrl);
    }
    map['last_panel'] = Variable<int>(lastPanel);
    if (!nullToAbsent || latestChapter != null) {
      map['latest_chapter'] = Variable<double>(latestChapter);
    }
    if (!nullToAbsent || readChapter != null) {
      map['read_chapter'] = Variable<double>(readChapter);
    }
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<String>(checkedAt);
    }
    if (!nullToAbsent || openedAt != null) {
      map['opened_at'] = Variable<String>(openedAt);
    }
    map['added_at'] = Variable<String>(addedAt);
    return map;
  }

  WebSeriesRowsCompanion toCompanion(bool nullToAbsent) {
    return WebSeriesRowsCompanion(
      url: Value(url),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      lastChapterUrl: lastChapterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChapterUrl),
      lastPanel: Value(lastPanel),
      latestChapter: latestChapter == null && nullToAbsent
          ? const Value.absent()
          : Value(latestChapter),
      readChapter: readChapter == null && nullToAbsent
          ? const Value.absent()
          : Value(readChapter),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
      openedAt: openedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(openedAt),
      addedAt: Value(addedAt),
    );
  }

  factory WebSeriesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WebSeriesRow(
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      lastChapterUrl: serializer.fromJson<String?>(json['lastChapterUrl']),
      lastPanel: serializer.fromJson<int>(json['lastPanel']),
      latestChapter: serializer.fromJson<double?>(json['latestChapter']),
      readChapter: serializer.fromJson<double?>(json['readChapter']),
      checkedAt: serializer.fromJson<String?>(json['checkedAt']),
      openedAt: serializer.fromJson<String?>(json['openedAt']),
      addedAt: serializer.fromJson<String>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'lastChapterUrl': serializer.toJson<String?>(lastChapterUrl),
      'lastPanel': serializer.toJson<int>(lastPanel),
      'latestChapter': serializer.toJson<double?>(latestChapter),
      'readChapter': serializer.toJson<double?>(readChapter),
      'checkedAt': serializer.toJson<String?>(checkedAt),
      'openedAt': serializer.toJson<String?>(openedAt),
      'addedAt': serializer.toJson<String>(addedAt),
    };
  }

  WebSeriesRow copyWith({
    String? url,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    Value<String?> lastChapterUrl = const Value.absent(),
    int? lastPanel,
    Value<double?> latestChapter = const Value.absent(),
    Value<double?> readChapter = const Value.absent(),
    Value<String?> checkedAt = const Value.absent(),
    Value<String?> openedAt = const Value.absent(),
    String? addedAt,
  }) => WebSeriesRow(
    url: url ?? this.url,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    lastChapterUrl: lastChapterUrl.present
        ? lastChapterUrl.value
        : this.lastChapterUrl,
    lastPanel: lastPanel ?? this.lastPanel,
    latestChapter: latestChapter.present
        ? latestChapter.value
        : this.latestChapter,
    readChapter: readChapter.present ? readChapter.value : this.readChapter,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
    openedAt: openedAt.present ? openedAt.value : this.openedAt,
    addedAt: addedAt ?? this.addedAt,
  );
  WebSeriesRow copyWithCompanion(WebSeriesRowsCompanion data) {
    return WebSeriesRow(
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      lastChapterUrl: data.lastChapterUrl.present
          ? data.lastChapterUrl.value
          : this.lastChapterUrl,
      lastPanel: data.lastPanel.present ? data.lastPanel.value : this.lastPanel,
      latestChapter: data.latestChapter.present
          ? data.latestChapter.value
          : this.latestChapter,
      readChapter: data.readChapter.present
          ? data.readChapter.value
          : this.readChapter,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WebSeriesRow(')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('lastChapterUrl: $lastChapterUrl, ')
          ..write('lastPanel: $lastPanel, ')
          ..write('latestChapter: $latestChapter, ')
          ..write('readChapter: $readChapter, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('openedAt: $openedAt, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    url,
    title,
    coverUrl,
    lastChapterUrl,
    lastPanel,
    latestChapter,
    readChapter,
    checkedAt,
    openedAt,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WebSeriesRow &&
          other.url == this.url &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.lastChapterUrl == this.lastChapterUrl &&
          other.lastPanel == this.lastPanel &&
          other.latestChapter == this.latestChapter &&
          other.readChapter == this.readChapter &&
          other.checkedAt == this.checkedAt &&
          other.openedAt == this.openedAt &&
          other.addedAt == this.addedAt);
}

class WebSeriesRowsCompanion extends UpdateCompanion<WebSeriesRow> {
  final Value<String> url;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String?> lastChapterUrl;
  final Value<int> lastPanel;
  final Value<double?> latestChapter;
  final Value<double?> readChapter;
  final Value<String?> checkedAt;
  final Value<String?> openedAt;
  final Value<String> addedAt;
  final Value<int> rowid;
  const WebSeriesRowsCompanion({
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.lastChapterUrl = const Value.absent(),
    this.lastPanel = const Value.absent(),
    this.latestChapter = const Value.absent(),
    this.readChapter = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WebSeriesRowsCompanion.insert({
    required String url,
    required String title,
    this.coverUrl = const Value.absent(),
    this.lastChapterUrl = const Value.absent(),
    this.lastPanel = const Value.absent(),
    this.latestChapter = const Value.absent(),
    this.readChapter = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.openedAt = const Value.absent(),
    required String addedAt,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       title = Value(title),
       addedAt = Value(addedAt);
  static Insertable<WebSeriesRow> custom({
    Expression<String>? url,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<String>? lastChapterUrl,
    Expression<int>? lastPanel,
    Expression<double>? latestChapter,
    Expression<double>? readChapter,
    Expression<String>? checkedAt,
    Expression<String>? openedAt,
    Expression<String>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (lastChapterUrl != null) 'last_chapter_url': lastChapterUrl,
      if (lastPanel != null) 'last_panel': lastPanel,
      if (latestChapter != null) 'latest_chapter': latestChapter,
      if (readChapter != null) 'read_chapter': readChapter,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (openedAt != null) 'opened_at': openedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WebSeriesRowsCompanion copyWith({
    Value<String>? url,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String?>? lastChapterUrl,
    Value<int>? lastPanel,
    Value<double?>? latestChapter,
    Value<double?>? readChapter,
    Value<String?>? checkedAt,
    Value<String?>? openedAt,
    Value<String>? addedAt,
    Value<int>? rowid,
  }) {
    return WebSeriesRowsCompanion(
      url: url ?? this.url,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      lastChapterUrl: lastChapterUrl ?? this.lastChapterUrl,
      lastPanel: lastPanel ?? this.lastPanel,
      latestChapter: latestChapter ?? this.latestChapter,
      readChapter: readChapter ?? this.readChapter,
      checkedAt: checkedAt ?? this.checkedAt,
      openedAt: openedAt ?? this.openedAt,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (lastChapterUrl.present) {
      map['last_chapter_url'] = Variable<String>(lastChapterUrl.value);
    }
    if (lastPanel.present) {
      map['last_panel'] = Variable<int>(lastPanel.value);
    }
    if (latestChapter.present) {
      map['latest_chapter'] = Variable<double>(latestChapter.value);
    }
    if (readChapter.present) {
      map['read_chapter'] = Variable<double>(readChapter.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<String>(checkedAt.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<String>(openedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<String>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WebSeriesRowsCompanion(')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('lastChapterUrl: $lastChapterUrl, ')
          ..write('lastPanel: $lastPanel, ')
          ..write('latestChapter: $latestChapter, ')
          ..write('readChapter: $readChapter, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('openedAt: $openedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AwardRowsTable extends AwardRows
    with TableInfo<$AwardRowsTable, AwardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AwardRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _earnedAtMeta = const VerificationMeta(
    'earnedAt',
  );
  @override
  late final GeneratedColumn<String> earnedAt = GeneratedColumn<String>(
    'earned_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seenMeta = const VerificationMeta('seen');
  @override
  late final GeneratedColumn<bool> seen = GeneratedColumn<bool>(
    'seen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("seen" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, earnedAt, seen];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'award_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<AwardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('earned_at')) {
      context.handle(
        _earnedAtMeta,
        earnedAt.isAcceptableOrUnknown(data['earned_at']!, _earnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_earnedAtMeta);
    }
    if (data.containsKey('seen')) {
      context.handle(
        _seenMeta,
        seen.isAcceptableOrUnknown(data['seen']!, _seenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AwardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AwardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      earnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}earned_at'],
      )!,
      seen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}seen'],
      )!,
    );
  }

  @override
  $AwardRowsTable createAlias(String alias) {
    return $AwardRowsTable(attachedDatabase, alias);
  }
}

class AwardRow extends DataClass implements Insertable<AwardRow> {
  /// The badge's stable id — a ladder tier like `hours.6`, or `find.marathon`.
  final String id;
  final String earnedAt;

  /// False until it has been shown. The backfill of a reader's existing
  /// history writes these already seen, so shipping the feature does not
  /// announce a decade of reading in one go.
  final bool seen;
  const AwardRow({
    required this.id,
    required this.earnedAt,
    required this.seen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['earned_at'] = Variable<String>(earnedAt);
    map['seen'] = Variable<bool>(seen);
    return map;
  }

  AwardRowsCompanion toCompanion(bool nullToAbsent) {
    return AwardRowsCompanion(
      id: Value(id),
      earnedAt: Value(earnedAt),
      seen: Value(seen),
    );
  }

  factory AwardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AwardRow(
      id: serializer.fromJson<String>(json['id']),
      earnedAt: serializer.fromJson<String>(json['earnedAt']),
      seen: serializer.fromJson<bool>(json['seen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'earnedAt': serializer.toJson<String>(earnedAt),
      'seen': serializer.toJson<bool>(seen),
    };
  }

  AwardRow copyWith({String? id, String? earnedAt, bool? seen}) => AwardRow(
    id: id ?? this.id,
    earnedAt: earnedAt ?? this.earnedAt,
    seen: seen ?? this.seen,
  );
  AwardRow copyWithCompanion(AwardRowsCompanion data) {
    return AwardRow(
      id: data.id.present ? data.id.value : this.id,
      earnedAt: data.earnedAt.present ? data.earnedAt.value : this.earnedAt,
      seen: data.seen.present ? data.seen.value : this.seen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AwardRow(')
          ..write('id: $id, ')
          ..write('earnedAt: $earnedAt, ')
          ..write('seen: $seen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, earnedAt, seen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AwardRow &&
          other.id == this.id &&
          other.earnedAt == this.earnedAt &&
          other.seen == this.seen);
}

class AwardRowsCompanion extends UpdateCompanion<AwardRow> {
  final Value<String> id;
  final Value<String> earnedAt;
  final Value<bool> seen;
  final Value<int> rowid;
  const AwardRowsCompanion({
    this.id = const Value.absent(),
    this.earnedAt = const Value.absent(),
    this.seen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AwardRowsCompanion.insert({
    required String id,
    required String earnedAt,
    this.seen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       earnedAt = Value(earnedAt);
  static Insertable<AwardRow> custom({
    Expression<String>? id,
    Expression<String>? earnedAt,
    Expression<bool>? seen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (earnedAt != null) 'earned_at': earnedAt,
      if (seen != null) 'seen': seen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AwardRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? earnedAt,
    Value<bool>? seen,
    Value<int>? rowid,
  }) {
    return AwardRowsCompanion(
      id: id ?? this.id,
      earnedAt: earnedAt ?? this.earnedAt,
      seen: seen ?? this.seen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (earnedAt.present) {
      map['earned_at'] = Variable<String>(earnedAt.value);
    }
    if (seen.present) {
      map['seen'] = Variable<bool>(seen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AwardRowsCompanion(')
          ..write('id: $id, ')
          ..write('earnedAt: $earnedAt, ')
          ..write('seen: $seen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesVectorRowsTable extends SeriesVectorRows
    with TableInfo<$SeriesVectorRowsTable, SeriesVectorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesVectorRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vectorMeta = const VerificationMeta('vector');
  @override
  late final GeneratedColumn<Uint8List> vector = GeneratedColumn<Uint8List>(
    'vector',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dimensionsMeta = const VerificationMeta(
    'dimensions',
  );
  @override
  late final GeneratedColumn<int> dimensions = GeneratedColumn<int>(
    'dimensions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textHashMeta = const VerificationMeta(
    'textHash',
  );
  @override
  late final GeneratedColumn<String> textHash = GeneratedColumn<String>(
    'text_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    vector,
    dimensions,
    textHash,
    model,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_vector_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesVectorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('vector')) {
      context.handle(
        _vectorMeta,
        vector.isAcceptableOrUnknown(data['vector']!, _vectorMeta),
      );
    } else if (isInserting) {
      context.missing(_vectorMeta);
    }
    if (data.containsKey('dimensions')) {
      context.handle(
        _dimensionsMeta,
        dimensions.isAcceptableOrUnknown(data['dimensions']!, _dimensionsMeta),
      );
    } else if (isInserting) {
      context.missing(_dimensionsMeta);
    }
    if (data.containsKey('text_hash')) {
      context.handle(
        _textHashMeta,
        textHash.isAcceptableOrUnknown(data['text_hash']!, _textHashMeta),
      );
    } else if (isInserting) {
      context.missing(_textHashMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId};
  @override
  SeriesVectorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesVectorRow(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      vector: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}vector'],
      )!,
      dimensions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dimensions'],
      )!,
      textHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_hash'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SeriesVectorRowsTable createAlias(String alias) {
    return $SeriesVectorRowsTable(attachedDatabase, alias);
  }
}

class SeriesVectorRow extends DataClass implements Insertable<SeriesVectorRow> {
  final int seriesId;

  /// Float32 little-endian, [dimensions] of them. A BLOB rather than a
  /// JSON array: 384 doubles as text is ~9KB per book and 9MB across the
  /// library, against 1.5KB and 1.5MB packed.
  final Uint8List vector;
  final int dimensions;

  /// Hash of the exact text embedded, so a changed blurb re-indexes and an
  /// unchanged one never does.
  final String textHash;

  /// Which model produced it. A different model's vectors are not
  /// comparable with these, so swapping models has to invalidate the index
  /// rather than silently mix two spaces.
  final String model;
  final String updatedAt;
  const SeriesVectorRow({
    required this.seriesId,
    required this.vector,
    required this.dimensions,
    required this.textHash,
    required this.model,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<int>(seriesId);
    map['vector'] = Variable<Uint8List>(vector);
    map['dimensions'] = Variable<int>(dimensions);
    map['text_hash'] = Variable<String>(textHash);
    map['model'] = Variable<String>(model);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  SeriesVectorRowsCompanion toCompanion(bool nullToAbsent) {
    return SeriesVectorRowsCompanion(
      seriesId: Value(seriesId),
      vector: Value(vector),
      dimensions: Value(dimensions),
      textHash: Value(textHash),
      model: Value(model),
      updatedAt: Value(updatedAt),
    );
  }

  factory SeriesVectorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesVectorRow(
      seriesId: serializer.fromJson<int>(json['seriesId']),
      vector: serializer.fromJson<Uint8List>(json['vector']),
      dimensions: serializer.fromJson<int>(json['dimensions']),
      textHash: serializer.fromJson<String>(json['textHash']),
      model: serializer.fromJson<String>(json['model']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<int>(seriesId),
      'vector': serializer.toJson<Uint8List>(vector),
      'dimensions': serializer.toJson<int>(dimensions),
      'textHash': serializer.toJson<String>(textHash),
      'model': serializer.toJson<String>(model),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  SeriesVectorRow copyWith({
    int? seriesId,
    Uint8List? vector,
    int? dimensions,
    String? textHash,
    String? model,
    String? updatedAt,
  }) => SeriesVectorRow(
    seriesId: seriesId ?? this.seriesId,
    vector: vector ?? this.vector,
    dimensions: dimensions ?? this.dimensions,
    textHash: textHash ?? this.textHash,
    model: model ?? this.model,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SeriesVectorRow copyWithCompanion(SeriesVectorRowsCompanion data) {
    return SeriesVectorRow(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      vector: data.vector.present ? data.vector.value : this.vector,
      dimensions: data.dimensions.present
          ? data.dimensions.value
          : this.dimensions,
      textHash: data.textHash.present ? data.textHash.value : this.textHash,
      model: data.model.present ? data.model.value : this.model,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesVectorRow(')
          ..write('seriesId: $seriesId, ')
          ..write('vector: $vector, ')
          ..write('dimensions: $dimensions, ')
          ..write('textHash: $textHash, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seriesId,
    $driftBlobEquality.hash(vector),
    dimensions,
    textHash,
    model,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesVectorRow &&
          other.seriesId == this.seriesId &&
          $driftBlobEquality.equals(other.vector, this.vector) &&
          other.dimensions == this.dimensions &&
          other.textHash == this.textHash &&
          other.model == this.model &&
          other.updatedAt == this.updatedAt);
}

class SeriesVectorRowsCompanion extends UpdateCompanion<SeriesVectorRow> {
  final Value<int> seriesId;
  final Value<Uint8List> vector;
  final Value<int> dimensions;
  final Value<String> textHash;
  final Value<String> model;
  final Value<String> updatedAt;
  const SeriesVectorRowsCompanion({
    this.seriesId = const Value.absent(),
    this.vector = const Value.absent(),
    this.dimensions = const Value.absent(),
    this.textHash = const Value.absent(),
    this.model = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SeriesVectorRowsCompanion.insert({
    this.seriesId = const Value.absent(),
    required Uint8List vector,
    required int dimensions,
    required String textHash,
    required String model,
    required String updatedAt,
  }) : vector = Value(vector),
       dimensions = Value(dimensions),
       textHash = Value(textHash),
       model = Value(model),
       updatedAt = Value(updatedAt);
  static Insertable<SeriesVectorRow> custom({
    Expression<int>? seriesId,
    Expression<Uint8List>? vector,
    Expression<int>? dimensions,
    Expression<String>? textHash,
    Expression<String>? model,
    Expression<String>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (vector != null) 'vector': vector,
      if (dimensions != null) 'dimensions': dimensions,
      if (textHash != null) 'text_hash': textHash,
      if (model != null) 'model': model,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SeriesVectorRowsCompanion copyWith({
    Value<int>? seriesId,
    Value<Uint8List>? vector,
    Value<int>? dimensions,
    Value<String>? textHash,
    Value<String>? model,
    Value<String>? updatedAt,
  }) {
    return SeriesVectorRowsCompanion(
      seriesId: seriesId ?? this.seriesId,
      vector: vector ?? this.vector,
      dimensions: dimensions ?? this.dimensions,
      textHash: textHash ?? this.textHash,
      model: model ?? this.model,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (vector.present) {
      map['vector'] = Variable<Uint8List>(vector.value);
    }
    if (dimensions.present) {
      map['dimensions'] = Variable<int>(dimensions.value);
    }
    if (textHash.present) {
      map['text_hash'] = Variable<String>(textHash.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesVectorRowsCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('vector: $vector, ')
          ..write('dimensions: $dimensions, ')
          ..write('textHash: $textHash, ')
          ..write('model: $model, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $KvRowsTable extends KvRows with TableInfo<$KvRowsTable, KvRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KvRowsTable createAlias(String alias) {
    return $KvRowsTable(attachedDatabase, alias);
  }
}

class KvRow extends DataClass implements Insertable<KvRow> {
  final String key;
  final String value;
  const KvRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvRowsCompanion toCompanion(bool nullToAbsent) {
    return KvRowsCompanion(key: Value(key), value: Value(value));
  }

  factory KvRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvRow copyWith({String? key, String? value}) =>
      KvRow(key: key ?? this.key, value: value ?? this.value);
  KvRow copyWithCompanion(KvRowsCompanion data) {
    return KvRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvRow && other.key == this.key && other.value == this.value);
}

class KvRowsCompanion extends UpdateCompanion<KvRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KvRowsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvRowsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvRowsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KvRowsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvRowsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ReadingProgressRowsTable readingProgressRows =
      $ReadingProgressRowsTable(this);
  late final $BookmarkRowsTable bookmarkRows = $BookmarkRowsTable(this);
  late final $CollectionRowsTable collectionRows = $CollectionRowsTable(this);
  late final $DailyActivityRowsTable dailyActivityRows =
      $DailyActivityRowsTable(this);
  late final $VolumeActivityRowsTable volumeActivityRows =
      $VolumeActivityRowsTable(this);
  late final $RecOutcomeRowsTable recOutcomeRows = $RecOutcomeRowsTable(this);
  late final $WebSeriesRowsTable webSeriesRows = $WebSeriesRowsTable(this);
  late final $AwardRowsTable awardRows = $AwardRowsTable(this);
  late final $SeriesVectorRowsTable seriesVectorRows = $SeriesVectorRowsTable(
    this,
  );
  late final $KvRowsTable kvRows = $KvRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    readingProgressRows,
    bookmarkRows,
    collectionRows,
    dailyActivityRows,
    volumeActivityRows,
    recOutcomeRows,
    webSeriesRows,
    awardRows,
    seriesVectorRows,
    kvRows,
  ];
}

typedef $$ReadingProgressRowsTableCreateCompanionBuilder =
    ReadingProgressRowsCompanion Function({
      required String volumeKey,
      Value<int> chapterIndex,
      Value<int> blockIndex,
      Value<int> blockChar,
      Value<String?> chapterPath,
      Value<int> chapterCount,
      Value<String?> updatedAt,
      Value<bool> endReached,
      Value<String?> volumeJson,
      Value<bool> hidden,
      Value<String?> hiddenAt,
      Value<String?> ttsResume,
      Value<int> rowid,
    });
typedef $$ReadingProgressRowsTableUpdateCompanionBuilder =
    ReadingProgressRowsCompanion Function({
      Value<String> volumeKey,
      Value<int> chapterIndex,
      Value<int> blockIndex,
      Value<int> blockChar,
      Value<String?> chapterPath,
      Value<int> chapterCount,
      Value<String?> updatedAt,
      Value<bool> endReached,
      Value<String?> volumeJson,
      Value<bool> hidden,
      Value<String?> hiddenAt,
      Value<String?> ttsResume,
      Value<int> rowid,
    });

class $$ReadingProgressRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockChar => $composableBuilder(
    column: $table.blockChar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get endReached => $composableBuilder(
    column: $table.endReached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get volumeJson => $composableBuilder(
    column: $table.volumeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ttsResume => $composableBuilder(
    column: $table.ttsResume,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingProgressRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockChar => $composableBuilder(
    column: $table.blockChar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get endReached => $composableBuilder(
    column: $table.endReached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get volumeJson => $composableBuilder(
    column: $table.volumeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ttsResume => $composableBuilder(
    column: $table.ttsResume,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingProgressRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get volumeKey =>
      $composableBuilder(column: $table.volumeKey, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get blockChar =>
      $composableBuilder(column: $table.blockChar, builder: (column) => column);

  GeneratedColumn<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get endReached => $composableBuilder(
    column: $table.endReached,
    builder: (column) => column,
  );

  GeneratedColumn<String> get volumeJson => $composableBuilder(
    column: $table.volumeJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<String> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => column);

  GeneratedColumn<String> get ttsResume =>
      $composableBuilder(column: $table.ttsResume, builder: (column) => column);
}

class $$ReadingProgressRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressRowsTable,
          ReadingProgressRow,
          $$ReadingProgressRowsTableFilterComposer,
          $$ReadingProgressRowsTableOrderingComposer,
          $$ReadingProgressRowsTableAnnotationComposer,
          $$ReadingProgressRowsTableCreateCompanionBuilder,
          $$ReadingProgressRowsTableUpdateCompanionBuilder,
          (
            ReadingProgressRow,
            BaseReferences<
              _$AppDatabase,
              $ReadingProgressRowsTable,
              ReadingProgressRow
            >,
          ),
          ReadingProgressRow,
          PrefetchHooks Function()
        > {
  $$ReadingProgressRowsTableTableManager(
    _$AppDatabase db,
    $ReadingProgressRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingProgressRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> volumeKey = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> blockIndex = const Value.absent(),
                Value<int> blockChar = const Value.absent(),
                Value<String?> chapterPath = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<bool> endReached = const Value.absent(),
                Value<String?> volumeJson = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> hiddenAt = const Value.absent(),
                Value<String?> ttsResume = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRowsCompanion(
                volumeKey: volumeKey,
                chapterIndex: chapterIndex,
                blockIndex: blockIndex,
                blockChar: blockChar,
                chapterPath: chapterPath,
                chapterCount: chapterCount,
                updatedAt: updatedAt,
                endReached: endReached,
                volumeJson: volumeJson,
                hidden: hidden,
                hiddenAt: hiddenAt,
                ttsResume: ttsResume,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String volumeKey,
                Value<int> chapterIndex = const Value.absent(),
                Value<int> blockIndex = const Value.absent(),
                Value<int> blockChar = const Value.absent(),
                Value<String?> chapterPath = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<bool> endReached = const Value.absent(),
                Value<String?> volumeJson = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> hiddenAt = const Value.absent(),
                Value<String?> ttsResume = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRowsCompanion.insert(
                volumeKey: volumeKey,
                chapterIndex: chapterIndex,
                blockIndex: blockIndex,
                blockChar: blockChar,
                chapterPath: chapterPath,
                chapterCount: chapterCount,
                updatedAt: updatedAt,
                endReached: endReached,
                volumeJson: volumeJson,
                hidden: hidden,
                hiddenAt: hiddenAt,
                ttsResume: ttsResume,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingProgressRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressRowsTable,
      ReadingProgressRow,
      $$ReadingProgressRowsTableFilterComposer,
      $$ReadingProgressRowsTableOrderingComposer,
      $$ReadingProgressRowsTableAnnotationComposer,
      $$ReadingProgressRowsTableCreateCompanionBuilder,
      $$ReadingProgressRowsTableUpdateCompanionBuilder,
      (
        ReadingProgressRow,
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressRowsTable,
          ReadingProgressRow
        >,
      ),
      ReadingProgressRow,
      PrefetchHooks Function()
    >;
typedef $$BookmarkRowsTableCreateCompanionBuilder =
    BookmarkRowsCompanion Function({
      required String volumeKey,
      required String bookmarkId,
      Value<int> chapterIndex,
      Value<int> blockIndex,
      Value<String> chapterTitle,
      Value<String> snippet,
      Value<String> createdAt,
      Value<bool> isHighlight,
      Value<String> note,
      Value<String> color,
      Value<int?> startChar,
      Value<int?> endChar,
      Value<int?> endBlockIndex,
      Value<String> selectedText,
      Value<int> rowid,
    });
typedef $$BookmarkRowsTableUpdateCompanionBuilder =
    BookmarkRowsCompanion Function({
      Value<String> volumeKey,
      Value<String> bookmarkId,
      Value<int> chapterIndex,
      Value<int> blockIndex,
      Value<String> chapterTitle,
      Value<String> snippet,
      Value<String> createdAt,
      Value<bool> isHighlight,
      Value<String> note,
      Value<String> color,
      Value<int?> startChar,
      Value<int?> endChar,
      Value<int?> endBlockIndex,
      Value<String> selectedText,
      Value<int> rowid,
    });

class $$BookmarkRowsTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarkRowsTable> {
  $$BookmarkRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookmarkId => $composableBuilder(
    column: $table.bookmarkId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHighlight => $composableBuilder(
    column: $table.isHighlight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startChar => $composableBuilder(
    column: $table.startChar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endChar => $composableBuilder(
    column: $table.endChar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endBlockIndex => $composableBuilder(
    column: $table.endBlockIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookmarkRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarkRowsTable> {
  $$BookmarkRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookmarkId => $composableBuilder(
    column: $table.bookmarkId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHighlight => $composableBuilder(
    column: $table.isHighlight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startChar => $composableBuilder(
    column: $table.startChar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endChar => $composableBuilder(
    column: $table.endChar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endBlockIndex => $composableBuilder(
    column: $table.endBlockIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookmarkRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarkRowsTable> {
  $$BookmarkRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get volumeKey =>
      $composableBuilder(column: $table.volumeKey, builder: (column) => column);

  GeneratedColumn<String> get bookmarkId => $composableBuilder(
    column: $table.bookmarkId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snippet =>
      $composableBuilder(column: $table.snippet, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isHighlight => $composableBuilder(
    column: $table.isHighlight,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get startChar =>
      $composableBuilder(column: $table.startChar, builder: (column) => column);

  GeneratedColumn<int> get endChar =>
      $composableBuilder(column: $table.endChar, builder: (column) => column);

  GeneratedColumn<int> get endBlockIndex => $composableBuilder(
    column: $table.endBlockIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => column,
  );
}

class $$BookmarkRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarkRowsTable,
          BookmarkRow,
          $$BookmarkRowsTableFilterComposer,
          $$BookmarkRowsTableOrderingComposer,
          $$BookmarkRowsTableAnnotationComposer,
          $$BookmarkRowsTableCreateCompanionBuilder,
          $$BookmarkRowsTableUpdateCompanionBuilder,
          (
            BookmarkRow,
            BaseReferences<_$AppDatabase, $BookmarkRowsTable, BookmarkRow>,
          ),
          BookmarkRow,
          PrefetchHooks Function()
        > {
  $$BookmarkRowsTableTableManager(_$AppDatabase db, $BookmarkRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarkRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarkRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarkRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> volumeKey = const Value.absent(),
                Value<String> bookmarkId = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> blockIndex = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<bool> isHighlight = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int?> startChar = const Value.absent(),
                Value<int?> endChar = const Value.absent(),
                Value<int?> endBlockIndex = const Value.absent(),
                Value<String> selectedText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarkRowsCompanion(
                volumeKey: volumeKey,
                bookmarkId: bookmarkId,
                chapterIndex: chapterIndex,
                blockIndex: blockIndex,
                chapterTitle: chapterTitle,
                snippet: snippet,
                createdAt: createdAt,
                isHighlight: isHighlight,
                note: note,
                color: color,
                startChar: startChar,
                endChar: endChar,
                endBlockIndex: endBlockIndex,
                selectedText: selectedText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String volumeKey,
                required String bookmarkId,
                Value<int> chapterIndex = const Value.absent(),
                Value<int> blockIndex = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<bool> isHighlight = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int?> startChar = const Value.absent(),
                Value<int?> endChar = const Value.absent(),
                Value<int?> endBlockIndex = const Value.absent(),
                Value<String> selectedText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarkRowsCompanion.insert(
                volumeKey: volumeKey,
                bookmarkId: bookmarkId,
                chapterIndex: chapterIndex,
                blockIndex: blockIndex,
                chapterTitle: chapterTitle,
                snippet: snippet,
                createdAt: createdAt,
                isHighlight: isHighlight,
                note: note,
                color: color,
                startChar: startChar,
                endChar: endChar,
                endBlockIndex: endBlockIndex,
                selectedText: selectedText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookmarkRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarkRowsTable,
      BookmarkRow,
      $$BookmarkRowsTableFilterComposer,
      $$BookmarkRowsTableOrderingComposer,
      $$BookmarkRowsTableAnnotationComposer,
      $$BookmarkRowsTableCreateCompanionBuilder,
      $$BookmarkRowsTableUpdateCompanionBuilder,
      (
        BookmarkRow,
        BaseReferences<_$AppDatabase, $BookmarkRowsTable, BookmarkRow>,
      ),
      BookmarkRow,
      PrefetchHooks Function()
    >;
typedef $$CollectionRowsTableCreateCompanionBuilder =
    CollectionRowsCompanion Function({
      required String id,
      required String name,
      Value<String> seriesIdsJson,
      Value<String> createdAt,
      Value<int> rowid,
    });
typedef $$CollectionRowsTableUpdateCompanionBuilder =
    CollectionRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> seriesIdsJson,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$CollectionRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionRowsTable> {
  $$CollectionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesIdsJson => $composableBuilder(
    column: $table.seriesIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionRowsTable> {
  $$CollectionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesIdsJson => $composableBuilder(
    column: $table.seriesIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionRowsTable> {
  $$CollectionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get seriesIdsJson => $composableBuilder(
    column: $table.seriesIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CollectionRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionRowsTable,
          CollectionRow,
          $$CollectionRowsTableFilterComposer,
          $$CollectionRowsTableOrderingComposer,
          $$CollectionRowsTableAnnotationComposer,
          $$CollectionRowsTableCreateCompanionBuilder,
          $$CollectionRowsTableUpdateCompanionBuilder,
          (
            CollectionRow,
            BaseReferences<_$AppDatabase, $CollectionRowsTable, CollectionRow>,
          ),
          CollectionRow,
          PrefetchHooks Function()
        > {
  $$CollectionRowsTableTableManager(
    _$AppDatabase db,
    $CollectionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> seriesIdsJson = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionRowsCompanion(
                id: id,
                name: name,
                seriesIdsJson: seriesIdsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> seriesIdsJson = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionRowsCompanion.insert(
                id: id,
                name: name,
                seriesIdsJson: seriesIdsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionRowsTable,
      CollectionRow,
      $$CollectionRowsTableFilterComposer,
      $$CollectionRowsTableOrderingComposer,
      $$CollectionRowsTableAnnotationComposer,
      $$CollectionRowsTableCreateCompanionBuilder,
      $$CollectionRowsTableUpdateCompanionBuilder,
      (
        CollectionRow,
        BaseReferences<_$AppDatabase, $CollectionRowsTable, CollectionRow>,
      ),
      CollectionRow,
      PrefetchHooks Function()
    >;
typedef $$DailyActivityRowsTableCreateCompanionBuilder =
    DailyActivityRowsCompanion Function({
      required String day,
      Value<int> seconds,
      Value<int> words,
      Value<int> rowid,
    });
typedef $$DailyActivityRowsTableUpdateCompanionBuilder =
    DailyActivityRowsCompanion Function({
      Value<String> day,
      Value<int> seconds,
      Value<int> words,
      Value<int> rowid,
    });

class $$DailyActivityRowsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyActivityRowsTable> {
  $$DailyActivityRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get words => $composableBuilder(
    column: $table.words,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyActivityRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyActivityRowsTable> {
  $$DailyActivityRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get words => $composableBuilder(
    column: $table.words,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyActivityRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyActivityRowsTable> {
  $$DailyActivityRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get seconds =>
      $composableBuilder(column: $table.seconds, builder: (column) => column);

  GeneratedColumn<int> get words =>
      $composableBuilder(column: $table.words, builder: (column) => column);
}

class $$DailyActivityRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyActivityRowsTable,
          DailyActivityRow,
          $$DailyActivityRowsTableFilterComposer,
          $$DailyActivityRowsTableOrderingComposer,
          $$DailyActivityRowsTableAnnotationComposer,
          $$DailyActivityRowsTableCreateCompanionBuilder,
          $$DailyActivityRowsTableUpdateCompanionBuilder,
          (
            DailyActivityRow,
            BaseReferences<
              _$AppDatabase,
              $DailyActivityRowsTable,
              DailyActivityRow
            >,
          ),
          DailyActivityRow,
          PrefetchHooks Function()
        > {
  $$DailyActivityRowsTableTableManager(
    _$AppDatabase db,
    $DailyActivityRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyActivityRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyActivityRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyActivityRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<int> seconds = const Value.absent(),
                Value<int> words = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyActivityRowsCompanion(
                day: day,
                seconds: seconds,
                words: words,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                Value<int> seconds = const Value.absent(),
                Value<int> words = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyActivityRowsCompanion.insert(
                day: day,
                seconds: seconds,
                words: words,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyActivityRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyActivityRowsTable,
      DailyActivityRow,
      $$DailyActivityRowsTableFilterComposer,
      $$DailyActivityRowsTableOrderingComposer,
      $$DailyActivityRowsTableAnnotationComposer,
      $$DailyActivityRowsTableCreateCompanionBuilder,
      $$DailyActivityRowsTableUpdateCompanionBuilder,
      (
        DailyActivityRow,
        BaseReferences<
          _$AppDatabase,
          $DailyActivityRowsTable,
          DailyActivityRow
        >,
      ),
      DailyActivityRow,
      PrefetchHooks Function()
    >;
typedef $$VolumeActivityRowsTableCreateCompanionBuilder =
    VolumeActivityRowsCompanion Function({
      required String volumeKey,
      Value<int> seconds,
      Value<int> words,
      Value<int> rowid,
    });
typedef $$VolumeActivityRowsTableUpdateCompanionBuilder =
    VolumeActivityRowsCompanion Function({
      Value<String> volumeKey,
      Value<int> seconds,
      Value<int> words,
      Value<int> rowid,
    });

class $$VolumeActivityRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VolumeActivityRowsTable> {
  $$VolumeActivityRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get words => $composableBuilder(
    column: $table.words,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VolumeActivityRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VolumeActivityRowsTable> {
  $$VolumeActivityRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get volumeKey => $composableBuilder(
    column: $table.volumeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get words => $composableBuilder(
    column: $table.words,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VolumeActivityRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VolumeActivityRowsTable> {
  $$VolumeActivityRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get volumeKey =>
      $composableBuilder(column: $table.volumeKey, builder: (column) => column);

  GeneratedColumn<int> get seconds =>
      $composableBuilder(column: $table.seconds, builder: (column) => column);

  GeneratedColumn<int> get words =>
      $composableBuilder(column: $table.words, builder: (column) => column);
}

class $$VolumeActivityRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VolumeActivityRowsTable,
          VolumeActivityRow,
          $$VolumeActivityRowsTableFilterComposer,
          $$VolumeActivityRowsTableOrderingComposer,
          $$VolumeActivityRowsTableAnnotationComposer,
          $$VolumeActivityRowsTableCreateCompanionBuilder,
          $$VolumeActivityRowsTableUpdateCompanionBuilder,
          (
            VolumeActivityRow,
            BaseReferences<
              _$AppDatabase,
              $VolumeActivityRowsTable,
              VolumeActivityRow
            >,
          ),
          VolumeActivityRow,
          PrefetchHooks Function()
        > {
  $$VolumeActivityRowsTableTableManager(
    _$AppDatabase db,
    $VolumeActivityRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VolumeActivityRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VolumeActivityRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VolumeActivityRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> volumeKey = const Value.absent(),
                Value<int> seconds = const Value.absent(),
                Value<int> words = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VolumeActivityRowsCompanion(
                volumeKey: volumeKey,
                seconds: seconds,
                words: words,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String volumeKey,
                Value<int> seconds = const Value.absent(),
                Value<int> words = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VolumeActivityRowsCompanion.insert(
                volumeKey: volumeKey,
                seconds: seconds,
                words: words,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VolumeActivityRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VolumeActivityRowsTable,
      VolumeActivityRow,
      $$VolumeActivityRowsTableFilterComposer,
      $$VolumeActivityRowsTableOrderingComposer,
      $$VolumeActivityRowsTableAnnotationComposer,
      $$VolumeActivityRowsTableCreateCompanionBuilder,
      $$VolumeActivityRowsTableUpdateCompanionBuilder,
      (
        VolumeActivityRow,
        BaseReferences<
          _$AppDatabase,
          $VolumeActivityRowsTable,
          VolumeActivityRow
        >,
      ),
      VolumeActivityRow,
      PrefetchHooks Function()
    >;
typedef $$RecOutcomeRowsTableCreateCompanionBuilder =
    RecOutcomeRowsCompanion Function({
      Value<int> seriesId,
      Value<int> impressions,
      Value<int> taps,
      Value<String> lastShownDay,
      Value<String?> lastTapAt,
    });
typedef $$RecOutcomeRowsTableUpdateCompanionBuilder =
    RecOutcomeRowsCompanion Function({
      Value<int> seriesId,
      Value<int> impressions,
      Value<int> taps,
      Value<String> lastShownDay,
      Value<String?> lastTapAt,
    });

class $$RecOutcomeRowsTableFilterComposer
    extends Composer<_$AppDatabase, $RecOutcomeRowsTable> {
  $$RecOutcomeRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get impressions => $composableBuilder(
    column: $table.impressions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taps => $composableBuilder(
    column: $table.taps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastShownDay => $composableBuilder(
    column: $table.lastShownDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastTapAt => $composableBuilder(
    column: $table.lastTapAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecOutcomeRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecOutcomeRowsTable> {
  $$RecOutcomeRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get impressions => $composableBuilder(
    column: $table.impressions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taps => $composableBuilder(
    column: $table.taps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastShownDay => $composableBuilder(
    column: $table.lastShownDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastTapAt => $composableBuilder(
    column: $table.lastTapAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecOutcomeRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecOutcomeRowsTable> {
  $$RecOutcomeRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get impressions => $composableBuilder(
    column: $table.impressions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taps =>
      $composableBuilder(column: $table.taps, builder: (column) => column);

  GeneratedColumn<String> get lastShownDay => $composableBuilder(
    column: $table.lastShownDay,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastTapAt =>
      $composableBuilder(column: $table.lastTapAt, builder: (column) => column);
}

class $$RecOutcomeRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecOutcomeRowsTable,
          RecOutcomeRow,
          $$RecOutcomeRowsTableFilterComposer,
          $$RecOutcomeRowsTableOrderingComposer,
          $$RecOutcomeRowsTableAnnotationComposer,
          $$RecOutcomeRowsTableCreateCompanionBuilder,
          $$RecOutcomeRowsTableUpdateCompanionBuilder,
          (
            RecOutcomeRow,
            BaseReferences<_$AppDatabase, $RecOutcomeRowsTable, RecOutcomeRow>,
          ),
          RecOutcomeRow,
          PrefetchHooks Function()
        > {
  $$RecOutcomeRowsTableTableManager(
    _$AppDatabase db,
    $RecOutcomeRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecOutcomeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecOutcomeRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecOutcomeRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<int> impressions = const Value.absent(),
                Value<int> taps = const Value.absent(),
                Value<String> lastShownDay = const Value.absent(),
                Value<String?> lastTapAt = const Value.absent(),
              }) => RecOutcomeRowsCompanion(
                seriesId: seriesId,
                impressions: impressions,
                taps: taps,
                lastShownDay: lastShownDay,
                lastTapAt: lastTapAt,
              ),
          createCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<int> impressions = const Value.absent(),
                Value<int> taps = const Value.absent(),
                Value<String> lastShownDay = const Value.absent(),
                Value<String?> lastTapAt = const Value.absent(),
              }) => RecOutcomeRowsCompanion.insert(
                seriesId: seriesId,
                impressions: impressions,
                taps: taps,
                lastShownDay: lastShownDay,
                lastTapAt: lastTapAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecOutcomeRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecOutcomeRowsTable,
      RecOutcomeRow,
      $$RecOutcomeRowsTableFilterComposer,
      $$RecOutcomeRowsTableOrderingComposer,
      $$RecOutcomeRowsTableAnnotationComposer,
      $$RecOutcomeRowsTableCreateCompanionBuilder,
      $$RecOutcomeRowsTableUpdateCompanionBuilder,
      (
        RecOutcomeRow,
        BaseReferences<_$AppDatabase, $RecOutcomeRowsTable, RecOutcomeRow>,
      ),
      RecOutcomeRow,
      PrefetchHooks Function()
    >;
typedef $$WebSeriesRowsTableCreateCompanionBuilder =
    WebSeriesRowsCompanion Function({
      required String url,
      required String title,
      Value<String?> coverUrl,
      Value<String?> lastChapterUrl,
      Value<int> lastPanel,
      Value<double?> latestChapter,
      Value<double?> readChapter,
      Value<String?> checkedAt,
      Value<String?> openedAt,
      required String addedAt,
      Value<int> rowid,
    });
typedef $$WebSeriesRowsTableUpdateCompanionBuilder =
    WebSeriesRowsCompanion Function({
      Value<String> url,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String?> lastChapterUrl,
      Value<int> lastPanel,
      Value<double?> latestChapter,
      Value<double?> readChapter,
      Value<String?> checkedAt,
      Value<String?> openedAt,
      Value<String> addedAt,
      Value<int> rowid,
    });

class $$WebSeriesRowsTableFilterComposer
    extends Composer<_$AppDatabase, $WebSeriesRowsTable> {
  $$WebSeriesRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastChapterUrl => $composableBuilder(
    column: $table.lastChapterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPanel => $composableBuilder(
    column: $table.lastPanel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latestChapter => $composableBuilder(
    column: $table.latestChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get readChapter => $composableBuilder(
    column: $table.readChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WebSeriesRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $WebSeriesRowsTable> {
  $$WebSeriesRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastChapterUrl => $composableBuilder(
    column: $table.lastChapterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPanel => $composableBuilder(
    column: $table.lastPanel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latestChapter => $composableBuilder(
    column: $table.latestChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get readChapter => $composableBuilder(
    column: $table.readChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WebSeriesRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WebSeriesRowsTable> {
  $$WebSeriesRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get lastChapterUrl => $composableBuilder(
    column: $table.lastChapterUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPanel =>
      $composableBuilder(column: $table.lastPanel, builder: (column) => column);

  GeneratedColumn<double> get latestChapter => $composableBuilder(
    column: $table.latestChapter,
    builder: (column) => column,
  );

  GeneratedColumn<double> get readChapter => $composableBuilder(
    column: $table.readChapter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<String> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<String> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$WebSeriesRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WebSeriesRowsTable,
          WebSeriesRow,
          $$WebSeriesRowsTableFilterComposer,
          $$WebSeriesRowsTableOrderingComposer,
          $$WebSeriesRowsTableAnnotationComposer,
          $$WebSeriesRowsTableCreateCompanionBuilder,
          $$WebSeriesRowsTableUpdateCompanionBuilder,
          (
            WebSeriesRow,
            BaseReferences<_$AppDatabase, $WebSeriesRowsTable, WebSeriesRow>,
          ),
          WebSeriesRow,
          PrefetchHooks Function()
        > {
  $$WebSeriesRowsTableTableManager(_$AppDatabase db, $WebSeriesRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WebSeriesRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WebSeriesRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WebSeriesRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> lastChapterUrl = const Value.absent(),
                Value<int> lastPanel = const Value.absent(),
                Value<double?> latestChapter = const Value.absent(),
                Value<double?> readChapter = const Value.absent(),
                Value<String?> checkedAt = const Value.absent(),
                Value<String?> openedAt = const Value.absent(),
                Value<String> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WebSeriesRowsCompanion(
                url: url,
                title: title,
                coverUrl: coverUrl,
                lastChapterUrl: lastChapterUrl,
                lastPanel: lastPanel,
                latestChapter: latestChapter,
                readChapter: readChapter,
                checkedAt: checkedAt,
                openedAt: openedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> lastChapterUrl = const Value.absent(),
                Value<int> lastPanel = const Value.absent(),
                Value<double?> latestChapter = const Value.absent(),
                Value<double?> readChapter = const Value.absent(),
                Value<String?> checkedAt = const Value.absent(),
                Value<String?> openedAt = const Value.absent(),
                required String addedAt,
                Value<int> rowid = const Value.absent(),
              }) => WebSeriesRowsCompanion.insert(
                url: url,
                title: title,
                coverUrl: coverUrl,
                lastChapterUrl: lastChapterUrl,
                lastPanel: lastPanel,
                latestChapter: latestChapter,
                readChapter: readChapter,
                checkedAt: checkedAt,
                openedAt: openedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WebSeriesRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WebSeriesRowsTable,
      WebSeriesRow,
      $$WebSeriesRowsTableFilterComposer,
      $$WebSeriesRowsTableOrderingComposer,
      $$WebSeriesRowsTableAnnotationComposer,
      $$WebSeriesRowsTableCreateCompanionBuilder,
      $$WebSeriesRowsTableUpdateCompanionBuilder,
      (
        WebSeriesRow,
        BaseReferences<_$AppDatabase, $WebSeriesRowsTable, WebSeriesRow>,
      ),
      WebSeriesRow,
      PrefetchHooks Function()
    >;
typedef $$AwardRowsTableCreateCompanionBuilder =
    AwardRowsCompanion Function({
      required String id,
      required String earnedAt,
      Value<bool> seen,
      Value<int> rowid,
    });
typedef $$AwardRowsTableUpdateCompanionBuilder =
    AwardRowsCompanion Function({
      Value<String> id,
      Value<String> earnedAt,
      Value<bool> seen,
      Value<int> rowid,
    });

class $$AwardRowsTableFilterComposer
    extends Composer<_$AppDatabase, $AwardRowsTable> {
  $$AwardRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get earnedAt => $composableBuilder(
    column: $table.earnedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get seen => $composableBuilder(
    column: $table.seen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AwardRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $AwardRowsTable> {
  $$AwardRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get earnedAt => $composableBuilder(
    column: $table.earnedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get seen => $composableBuilder(
    column: $table.seen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AwardRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AwardRowsTable> {
  $$AwardRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get earnedAt =>
      $composableBuilder(column: $table.earnedAt, builder: (column) => column);

  GeneratedColumn<bool> get seen =>
      $composableBuilder(column: $table.seen, builder: (column) => column);
}

class $$AwardRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AwardRowsTable,
          AwardRow,
          $$AwardRowsTableFilterComposer,
          $$AwardRowsTableOrderingComposer,
          $$AwardRowsTableAnnotationComposer,
          $$AwardRowsTableCreateCompanionBuilder,
          $$AwardRowsTableUpdateCompanionBuilder,
          (AwardRow, BaseReferences<_$AppDatabase, $AwardRowsTable, AwardRow>),
          AwardRow,
          PrefetchHooks Function()
        > {
  $$AwardRowsTableTableManager(_$AppDatabase db, $AwardRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AwardRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AwardRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AwardRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> earnedAt = const Value.absent(),
                Value<bool> seen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AwardRowsCompanion(
                id: id,
                earnedAt: earnedAt,
                seen: seen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String earnedAt,
                Value<bool> seen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AwardRowsCompanion.insert(
                id: id,
                earnedAt: earnedAt,
                seen: seen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AwardRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AwardRowsTable,
      AwardRow,
      $$AwardRowsTableFilterComposer,
      $$AwardRowsTableOrderingComposer,
      $$AwardRowsTableAnnotationComposer,
      $$AwardRowsTableCreateCompanionBuilder,
      $$AwardRowsTableUpdateCompanionBuilder,
      (AwardRow, BaseReferences<_$AppDatabase, $AwardRowsTable, AwardRow>),
      AwardRow,
      PrefetchHooks Function()
    >;
typedef $$SeriesVectorRowsTableCreateCompanionBuilder =
    SeriesVectorRowsCompanion Function({
      Value<int> seriesId,
      required Uint8List vector,
      required int dimensions,
      required String textHash,
      required String model,
      required String updatedAt,
    });
typedef $$SeriesVectorRowsTableUpdateCompanionBuilder =
    SeriesVectorRowsCompanion Function({
      Value<int> seriesId,
      Value<Uint8List> vector,
      Value<int> dimensions,
      Value<String> textHash,
      Value<String> model,
      Value<String> updatedAt,
    });

class $$SeriesVectorRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SeriesVectorRowsTable> {
  $$SeriesVectorRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dimensions => $composableBuilder(
    column: $table.dimensions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textHash => $composableBuilder(
    column: $table.textHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesVectorRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeriesVectorRowsTable> {
  $$SeriesVectorRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dimensions => $composableBuilder(
    column: $table.dimensions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textHash => $composableBuilder(
    column: $table.textHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesVectorRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeriesVectorRowsTable> {
  $$SeriesVectorRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<Uint8List> get vector =>
      $composableBuilder(column: $table.vector, builder: (column) => column);

  GeneratedColumn<int> get dimensions => $composableBuilder(
    column: $table.dimensions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textHash =>
      $composableBuilder(column: $table.textHash, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SeriesVectorRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeriesVectorRowsTable,
          SeriesVectorRow,
          $$SeriesVectorRowsTableFilterComposer,
          $$SeriesVectorRowsTableOrderingComposer,
          $$SeriesVectorRowsTableAnnotationComposer,
          $$SeriesVectorRowsTableCreateCompanionBuilder,
          $$SeriesVectorRowsTableUpdateCompanionBuilder,
          (
            SeriesVectorRow,
            BaseReferences<
              _$AppDatabase,
              $SeriesVectorRowsTable,
              SeriesVectorRow
            >,
          ),
          SeriesVectorRow,
          PrefetchHooks Function()
        > {
  $$SeriesVectorRowsTableTableManager(
    _$AppDatabase db,
    $SeriesVectorRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesVectorRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesVectorRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesVectorRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<Uint8List> vector = const Value.absent(),
                Value<int> dimensions = const Value.absent(),
                Value<String> textHash = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
              }) => SeriesVectorRowsCompanion(
                seriesId: seriesId,
                vector: vector,
                dimensions: dimensions,
                textHash: textHash,
                model: model,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                required Uint8List vector,
                required int dimensions,
                required String textHash,
                required String model,
                required String updatedAt,
              }) => SeriesVectorRowsCompanion.insert(
                seriesId: seriesId,
                vector: vector,
                dimensions: dimensions,
                textHash: textHash,
                model: model,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesVectorRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeriesVectorRowsTable,
      SeriesVectorRow,
      $$SeriesVectorRowsTableFilterComposer,
      $$SeriesVectorRowsTableOrderingComposer,
      $$SeriesVectorRowsTableAnnotationComposer,
      $$SeriesVectorRowsTableCreateCompanionBuilder,
      $$SeriesVectorRowsTableUpdateCompanionBuilder,
      (
        SeriesVectorRow,
        BaseReferences<_$AppDatabase, $SeriesVectorRowsTable, SeriesVectorRow>,
      ),
      SeriesVectorRow,
      PrefetchHooks Function()
    >;
typedef $$KvRowsTableCreateCompanionBuilder =
    KvRowsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$KvRowsTableUpdateCompanionBuilder =
    KvRowsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$KvRowsTableFilterComposer
    extends Composer<_$AppDatabase, $KvRowsTable> {
  $$KvRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $KvRowsTable> {
  $$KvRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KvRowsTable> {
  $$KvRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KvRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KvRowsTable,
          KvRow,
          $$KvRowsTableFilterComposer,
          $$KvRowsTableOrderingComposer,
          $$KvRowsTableAnnotationComposer,
          $$KvRowsTableCreateCompanionBuilder,
          $$KvRowsTableUpdateCompanionBuilder,
          (KvRow, BaseReferences<_$AppDatabase, $KvRowsTable, KvRow>),
          KvRow,
          PrefetchHooks Function()
        > {
  $$KvRowsTableTableManager(_$AppDatabase db, $KvRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvRowsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) =>
                  KvRowsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KvRowsTable,
      KvRow,
      $$KvRowsTableFilterComposer,
      $$KvRowsTableOrderingComposer,
      $$KvRowsTableAnnotationComposer,
      $$KvRowsTableCreateCompanionBuilder,
      $$KvRowsTableUpdateCompanionBuilder,
      (KvRow, BaseReferences<_$AppDatabase, $KvRowsTable, KvRow>),
      KvRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ReadingProgressRowsTableTableManager get readingProgressRows =>
      $$ReadingProgressRowsTableTableManager(_db, _db.readingProgressRows);
  $$BookmarkRowsTableTableManager get bookmarkRows =>
      $$BookmarkRowsTableTableManager(_db, _db.bookmarkRows);
  $$CollectionRowsTableTableManager get collectionRows =>
      $$CollectionRowsTableTableManager(_db, _db.collectionRows);
  $$DailyActivityRowsTableTableManager get dailyActivityRows =>
      $$DailyActivityRowsTableTableManager(_db, _db.dailyActivityRows);
  $$VolumeActivityRowsTableTableManager get volumeActivityRows =>
      $$VolumeActivityRowsTableTableManager(_db, _db.volumeActivityRows);
  $$RecOutcomeRowsTableTableManager get recOutcomeRows =>
      $$RecOutcomeRowsTableTableManager(_db, _db.recOutcomeRows);
  $$WebSeriesRowsTableTableManager get webSeriesRows =>
      $$WebSeriesRowsTableTableManager(_db, _db.webSeriesRows);
  $$AwardRowsTableTableManager get awardRows =>
      $$AwardRowsTableTableManager(_db, _db.awardRows);
  $$SeriesVectorRowsTableTableManager get seriesVectorRows =>
      $$SeriesVectorRowsTableTableManager(_db, _db.seriesVectorRows);
  $$KvRowsTableTableManager get kvRows =>
      $$KvRowsTableTableManager(_db, _db.kvRows);
}
