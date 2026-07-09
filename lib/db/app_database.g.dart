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
          ..write('color: $color')
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
          other.color == this.color);
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
  @override
  List<GeneratedColumn> get $columns => [day, seconds];
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
  const DailyActivityRow({required this.day, required this.seconds});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['seconds'] = Variable<int>(seconds);
    return map;
  }

  DailyActivityRowsCompanion toCompanion(bool nullToAbsent) {
    return DailyActivityRowsCompanion(day: Value(day), seconds: Value(seconds));
  }

  factory DailyActivityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyActivityRow(
      day: serializer.fromJson<String>(json['day']),
      seconds: serializer.fromJson<int>(json['seconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'seconds': serializer.toJson<int>(seconds),
    };
  }

  DailyActivityRow copyWith({String? day, int? seconds}) =>
      DailyActivityRow(day: day ?? this.day, seconds: seconds ?? this.seconds);
  DailyActivityRow copyWithCompanion(DailyActivityRowsCompanion data) {
    return DailyActivityRow(
      day: data.day.present ? data.day.value : this.day,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyActivityRow(')
          ..write('day: $day, ')
          ..write('seconds: $seconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, seconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyActivityRow &&
          other.day == this.day &&
          other.seconds == this.seconds);
}

class DailyActivityRowsCompanion extends UpdateCompanion<DailyActivityRow> {
  final Value<String> day;
  final Value<int> seconds;
  final Value<int> rowid;
  const DailyActivityRowsCompanion({
    this.day = const Value.absent(),
    this.seconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyActivityRowsCompanion.insert({
    required String day,
    this.seconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : day = Value(day);
  static Insertable<DailyActivityRow> custom({
    Expression<String>? day,
    Expression<int>? seconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (seconds != null) 'seconds': seconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyActivityRowsCompanion copyWith({
    Value<String>? day,
    Value<int>? seconds,
    Value<int>? rowid,
  }) {
    return DailyActivityRowsCompanion(
      day: day ?? this.day,
      seconds: seconds ?? this.seconds,
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
  @override
  List<GeneratedColumn> get $columns => [volumeKey, seconds];
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
  const VolumeActivityRow({required this.volumeKey, required this.seconds});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['volume_key'] = Variable<String>(volumeKey);
    map['seconds'] = Variable<int>(seconds);
    return map;
  }

  VolumeActivityRowsCompanion toCompanion(bool nullToAbsent) {
    return VolumeActivityRowsCompanion(
      volumeKey: Value(volumeKey),
      seconds: Value(seconds),
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
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'volumeKey': serializer.toJson<String>(volumeKey),
      'seconds': serializer.toJson<int>(seconds),
    };
  }

  VolumeActivityRow copyWith({String? volumeKey, int? seconds}) =>
      VolumeActivityRow(
        volumeKey: volumeKey ?? this.volumeKey,
        seconds: seconds ?? this.seconds,
      );
  VolumeActivityRow copyWithCompanion(VolumeActivityRowsCompanion data) {
    return VolumeActivityRow(
      volumeKey: data.volumeKey.present ? data.volumeKey.value : this.volumeKey,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VolumeActivityRow(')
          ..write('volumeKey: $volumeKey, ')
          ..write('seconds: $seconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(volumeKey, seconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VolumeActivityRow &&
          other.volumeKey == this.volumeKey &&
          other.seconds == this.seconds);
}

class VolumeActivityRowsCompanion extends UpdateCompanion<VolumeActivityRow> {
  final Value<String> volumeKey;
  final Value<int> seconds;
  final Value<int> rowid;
  const VolumeActivityRowsCompanion({
    this.volumeKey = const Value.absent(),
    this.seconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VolumeActivityRowsCompanion.insert({
    required String volumeKey,
    this.seconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : volumeKey = Value(volumeKey);
  static Insertable<VolumeActivityRow> custom({
    Expression<String>? volumeKey,
    Expression<int>? seconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (volumeKey != null) 'volume_key': volumeKey,
      if (seconds != null) 'seconds': seconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VolumeActivityRowsCompanion copyWith({
    Value<String>? volumeKey,
    Value<int>? seconds,
    Value<int>? rowid,
  }) {
    return VolumeActivityRowsCompanion(
      volumeKey: volumeKey ?? this.volumeKey,
      seconds: seconds ?? this.seconds,
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
          ..write('rowid: $rowid')
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
      Value<int> rowid,
    });
typedef $$DailyActivityRowsTableUpdateCompanionBuilder =
    DailyActivityRowsCompanion Function({
      Value<String> day,
      Value<int> seconds,
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
                Value<int> rowid = const Value.absent(),
              }) => DailyActivityRowsCompanion(
                day: day,
                seconds: seconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                Value<int> seconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyActivityRowsCompanion.insert(
                day: day,
                seconds: seconds,
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
      Value<int> rowid,
    });
typedef $$VolumeActivityRowsTableUpdateCompanionBuilder =
    VolumeActivityRowsCompanion Function({
      Value<String> volumeKey,
      Value<int> seconds,
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
                Value<int> rowid = const Value.absent(),
              }) => VolumeActivityRowsCompanion(
                volumeKey: volumeKey,
                seconds: seconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String volumeKey,
                Value<int> seconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VolumeActivityRowsCompanion.insert(
                volumeKey: volumeKey,
                seconds: seconds,
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
  $$KvRowsTableTableManager get kvRows =>
      $$KvRowsTableTableManager(_db, _db.kvRows);
}
