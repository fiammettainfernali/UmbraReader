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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ReadingProgressRowsTable readingProgressRows =
      $ReadingProgressRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [readingProgressRows];
}

typedef $$ReadingProgressRowsTableCreateCompanionBuilder =
    ReadingProgressRowsCompanion Function({
      required String volumeKey,
      Value<int> chapterIndex,
      Value<int> blockIndex,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ReadingProgressRowsTableTableManager get readingProgressRows =>
      $$ReadingProgressRowsTableTableManager(_db, _db.readingProgressRows);
}
