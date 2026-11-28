// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_database.dart';

// ignore_for_file: type=lint
class $TodoListRecordsTable extends TodoListRecords
    with TableInfo<$TodoListRecordsTable, TodoListRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoListRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountKey, id, position, payloadJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todo_list_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TodoListRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountKey, id};
  @override
  TodoListRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoListRecord(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $TodoListRecordsTable createAlias(String alias) {
    return $TodoListRecordsTable(attachedDatabase, alias);
  }
}

class TodoListRecord extends DataClass implements Insertable<TodoListRecord> {
  final String accountKey;
  final String id;
  final int position;
  final String payloadJson;
  const TodoListRecord({
    required this.accountKey,
    required this.id,
    required this.position,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['id'] = Variable<String>(id);
    map['position'] = Variable<int>(position);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  TodoListRecordsCompanion toCompanion(bool nullToAbsent) {
    return TodoListRecordsCompanion(
      accountKey: Value(accountKey),
      id: Value(id),
      position: Value(position),
      payloadJson: Value(payloadJson),
    );
  }

  factory TodoListRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoListRecord(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      id: serializer.fromJson<String>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'id': serializer.toJson<String>(id),
      'position': serializer.toJson<int>(position),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  TodoListRecord copyWith({
    String? accountKey,
    String? id,
    int? position,
    String? payloadJson,
  }) => TodoListRecord(
    accountKey: accountKey ?? this.accountKey,
    id: id ?? this.id,
    position: position ?? this.position,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  TodoListRecord copyWithCompanion(TodoListRecordsCompanion data) {
    return TodoListRecord(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoListRecord(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountKey, id, position, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoListRecord &&
          other.accountKey == this.accountKey &&
          other.id == this.id &&
          other.position == this.position &&
          other.payloadJson == this.payloadJson);
}

class TodoListRecordsCompanion extends UpdateCompanion<TodoListRecord> {
  final Value<String> accountKey;
  final Value<String> id;
  final Value<int> position;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const TodoListRecordsCompanion({
    this.accountKey = const Value.absent(),
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoListRecordsCompanion.insert({
    required String accountKey,
    required String id,
    required int position,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       id = Value(id),
       position = Value(position),
       payloadJson = Value(payloadJson);
  static Insertable<TodoListRecord> custom({
    Expression<String>? accountKey,
    Expression<String>? id,
    Expression<int>? position,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoListRecordsCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? id,
    Value<int>? position,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return TodoListRecordsCompanion(
      accountKey: accountKey ?? this.accountKey,
      id: id ?? this.id,
      position: position ?? this.position,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoListRecordsCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListGroupRecordsTable extends ListGroupRecords
    with TableInfo<$ListGroupRecordsTable, ListGroupRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListGroupRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountKey, id, position, payloadJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'list_group_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ListGroupRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountKey, id};
  @override
  ListGroupRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListGroupRecord(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $ListGroupRecordsTable createAlias(String alias) {
    return $ListGroupRecordsTable(attachedDatabase, alias);
  }
}

class ListGroupRecord extends DataClass implements Insertable<ListGroupRecord> {
  final String accountKey;
  final String id;
  final int position;
  final String payloadJson;
  const ListGroupRecord({
    required this.accountKey,
    required this.id,
    required this.position,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['id'] = Variable<String>(id);
    map['position'] = Variable<int>(position);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  ListGroupRecordsCompanion toCompanion(bool nullToAbsent) {
    return ListGroupRecordsCompanion(
      accountKey: Value(accountKey),
      id: Value(id),
      position: Value(position),
      payloadJson: Value(payloadJson),
    );
  }

  factory ListGroupRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListGroupRecord(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      id: serializer.fromJson<String>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'id': serializer.toJson<String>(id),
      'position': serializer.toJson<int>(position),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  ListGroupRecord copyWith({
    String? accountKey,
    String? id,
    int? position,
    String? payloadJson,
  }) => ListGroupRecord(
    accountKey: accountKey ?? this.accountKey,
    id: id ?? this.id,
    position: position ?? this.position,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  ListGroupRecord copyWithCompanion(ListGroupRecordsCompanion data) {
    return ListGroupRecord(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListGroupRecord(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountKey, id, position, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListGroupRecord &&
          other.accountKey == this.accountKey &&
          other.id == this.id &&
          other.position == this.position &&
          other.payloadJson == this.payloadJson);
}

class ListGroupRecordsCompanion extends UpdateCompanion<ListGroupRecord> {
  final Value<String> accountKey;
  final Value<String> id;
  final Value<int> position;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const ListGroupRecordsCompanion({
    this.accountKey = const Value.absent(),
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ListGroupRecordsCompanion.insert({
    required String accountKey,
    required String id,
    required int position,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       id = Value(id),
       position = Value(position),
       payloadJson = Value(payloadJson);
  static Insertable<ListGroupRecord> custom({
    Expression<String>? accountKey,
    Expression<String>? id,
    Expression<int>? position,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ListGroupRecordsCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? id,
    Value<int>? position,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return ListGroupRecordsCompanion(
      accountKey: accountKey ?? this.accountKey,
      id: id ?? this.id,
      position: position ?? this.position,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListGroupRecordsCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskItemRecordsTable extends TaskItemRecords
    with TableInfo<$TaskItemRecordsTable, TaskItemRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskItemRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<String> listId = GeneratedColumn<String>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountKey,
    id,
    listId,
    position,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_item_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskItemRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountKey, id};
  @override
  TaskItemRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskItemRecord(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $TaskItemRecordsTable createAlias(String alias) {
    return $TaskItemRecordsTable(attachedDatabase, alias);
  }
}

class TaskItemRecord extends DataClass implements Insertable<TaskItemRecord> {
  final String accountKey;
  final String id;
  final String listId;
  final int position;
  final String payloadJson;
  const TaskItemRecord({
    required this.accountKey,
    required this.id,
    required this.listId,
    required this.position,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['id'] = Variable<String>(id);
    map['list_id'] = Variable<String>(listId);
    map['position'] = Variable<int>(position);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  TaskItemRecordsCompanion toCompanion(bool nullToAbsent) {
    return TaskItemRecordsCompanion(
      accountKey: Value(accountKey),
      id: Value(id),
      listId: Value(listId),
      position: Value(position),
      payloadJson: Value(payloadJson),
    );
  }

  factory TaskItemRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskItemRecord(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      id: serializer.fromJson<String>(json['id']),
      listId: serializer.fromJson<String>(json['listId']),
      position: serializer.fromJson<int>(json['position']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'id': serializer.toJson<String>(id),
      'listId': serializer.toJson<String>(listId),
      'position': serializer.toJson<int>(position),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  TaskItemRecord copyWith({
    String? accountKey,
    String? id,
    String? listId,
    int? position,
    String? payloadJson,
  }) => TaskItemRecord(
    accountKey: accountKey ?? this.accountKey,
    id: id ?? this.id,
    listId: listId ?? this.listId,
    position: position ?? this.position,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  TaskItemRecord copyWithCompanion(TaskItemRecordsCompanion data) {
    return TaskItemRecord(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      position: data.position.present ? data.position.value : this.position,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskItemRecord(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountKey, id, listId, position, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskItemRecord &&
          other.accountKey == this.accountKey &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.position == this.position &&
          other.payloadJson == this.payloadJson);
}

class TaskItemRecordsCompanion extends UpdateCompanion<TaskItemRecord> {
  final Value<String> accountKey;
  final Value<String> id;
  final Value<String> listId;
  final Value<int> position;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const TaskItemRecordsCompanion({
    this.accountKey = const Value.absent(),
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.position = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskItemRecordsCompanion.insert({
    required String accountKey,
    required String id,
    required String listId,
    required int position,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       id = Value(id),
       listId = Value(listId),
       position = Value(position),
       payloadJson = Value(payloadJson);
  static Insertable<TaskItemRecord> custom({
    Expression<String>? accountKey,
    Expression<String>? id,
    Expression<String>? listId,
    Expression<int>? position,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (position != null) 'position': position,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskItemRecordsCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? id,
    Value<String>? listId,
    Value<int>? position,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return TaskItemRecordsCompanion(
      accountKey: accountKey ?? this.accountKey,
      id: id ?? this.id,
      listId: listId ?? this.listId,
      position: position ?? this.position,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<String>(listId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskItemRecordsCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMutationRecordsTable extends SyncMutationRecords
    with TableInfo<$SyncMutationRecordsTable, SyncMutationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMutationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountKey,
    kind,
    itemKey,
    position,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_mutation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMutationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountKey, kind, itemKey};
  @override
  SyncMutationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMutationRecord(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $SyncMutationRecordsTable createAlias(String alias) {
    return $SyncMutationRecordsTable(attachedDatabase, alias);
  }
}

class SyncMutationRecord extends DataClass
    implements Insertable<SyncMutationRecord> {
  final String accountKey;
  final String kind;
  final String itemKey;
  final int position;
  final String payloadJson;
  const SyncMutationRecord({
    required this.accountKey,
    required this.kind,
    required this.itemKey,
    required this.position,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['kind'] = Variable<String>(kind);
    map['item_key'] = Variable<String>(itemKey);
    map['position'] = Variable<int>(position);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  SyncMutationRecordsCompanion toCompanion(bool nullToAbsent) {
    return SyncMutationRecordsCompanion(
      accountKey: Value(accountKey),
      kind: Value(kind),
      itemKey: Value(itemKey),
      position: Value(position),
      payloadJson: Value(payloadJson),
    );
  }

  factory SyncMutationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMutationRecord(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      kind: serializer.fromJson<String>(json['kind']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      position: serializer.fromJson<int>(json['position']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'kind': serializer.toJson<String>(kind),
      'itemKey': serializer.toJson<String>(itemKey),
      'position': serializer.toJson<int>(position),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  SyncMutationRecord copyWith({
    String? accountKey,
    String? kind,
    String? itemKey,
    int? position,
    String? payloadJson,
  }) => SyncMutationRecord(
    accountKey: accountKey ?? this.accountKey,
    kind: kind ?? this.kind,
    itemKey: itemKey ?? this.itemKey,
    position: position ?? this.position,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  SyncMutationRecord copyWithCompanion(SyncMutationRecordsCompanion data) {
    return SyncMutationRecord(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      position: data.position.present ? data.position.value : this.position,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutationRecord(')
          ..write('accountKey: $accountKey, ')
          ..write('kind: $kind, ')
          ..write('itemKey: $itemKey, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountKey, kind, itemKey, position, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMutationRecord &&
          other.accountKey == this.accountKey &&
          other.kind == this.kind &&
          other.itemKey == this.itemKey &&
          other.position == this.position &&
          other.payloadJson == this.payloadJson);
}

class SyncMutationRecordsCompanion extends UpdateCompanion<SyncMutationRecord> {
  final Value<String> accountKey;
  final Value<String> kind;
  final Value<String> itemKey;
  final Value<int> position;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const SyncMutationRecordsCompanion({
    this.accountKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.position = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMutationRecordsCompanion.insert({
    required String accountKey,
    required String kind,
    required String itemKey,
    required int position,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       kind = Value(kind),
       itemKey = Value(itemKey),
       position = Value(position),
       payloadJson = Value(payloadJson);
  static Insertable<SyncMutationRecord> custom({
    Expression<String>? accountKey,
    Expression<String>? kind,
    Expression<String>? itemKey,
    Expression<int>? position,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (kind != null) 'kind': kind,
      if (itemKey != null) 'item_key': itemKey,
      if (position != null) 'position': position,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMutationRecordsCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? kind,
    Value<String>? itemKey,
    Value<int>? position,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return SyncMutationRecordsCompanion(
      accountKey: accountKey ?? this.accountKey,
      kind: kind ?? this.kind,
      itemKey: itemKey ?? this.itemKey,
      position: position ?? this.position,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutationRecordsCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('kind: $kind, ')
          ..write('itemKey: $itemKey, ')
          ..write('position: $position, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$TodoDatabase extends GeneratedDatabase {
  _$TodoDatabase(QueryExecutor e) : super(e);
  $TodoDatabaseManager get managers => $TodoDatabaseManager(this);
  late final $TodoListRecordsTable todoListRecords = $TodoListRecordsTable(
    this,
  );
  late final $ListGroupRecordsTable listGroupRecords = $ListGroupRecordsTable(
    this,
  );
  late final $TaskItemRecordsTable taskItemRecords = $TaskItemRecordsTable(
    this,
  );
  late final $SyncMutationRecordsTable syncMutationRecords =
      $SyncMutationRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    todoListRecords,
    listGroupRecords,
    taskItemRecords,
    syncMutationRecords,
  ];
}

typedef $$TodoListRecordsTableCreateCompanionBuilder =
    TodoListRecordsCompanion Function({
      required String accountKey,
      required String id,
      required int position,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$TodoListRecordsTableUpdateCompanionBuilder =
    TodoListRecordsCompanion Function({
      Value<String> accountKey,
      Value<String> id,
      Value<int> position,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$TodoListRecordsTableFilterComposer
    extends Composer<_$TodoDatabase, $TodoListRecordsTable> {
  $$TodoListRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodoListRecordsTableOrderingComposer
    extends Composer<_$TodoDatabase, $TodoListRecordsTable> {
  $$TodoListRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodoListRecordsTableAnnotationComposer
    extends Composer<_$TodoDatabase, $TodoListRecordsTable> {
  $$TodoListRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$TodoListRecordsTableTableManager
    extends
        RootTableManager<
          _$TodoDatabase,
          $TodoListRecordsTable,
          TodoListRecord,
          $$TodoListRecordsTableFilterComposer,
          $$TodoListRecordsTableOrderingComposer,
          $$TodoListRecordsTableAnnotationComposer,
          $$TodoListRecordsTableCreateCompanionBuilder,
          $$TodoListRecordsTableUpdateCompanionBuilder,
          (
            TodoListRecord,
            BaseReferences<
              _$TodoDatabase,
              $TodoListRecordsTable,
              TodoListRecord
            >,
          ),
          TodoListRecord,
          PrefetchHooks Function()
        > {
  $$TodoListRecordsTableTableManager(
    _$TodoDatabase db,
    $TodoListRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodoListRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodoListRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodoListRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodoListRecordsCompanion(
                accountKey: accountKey,
                id: id,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String id,
                required int position,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => TodoListRecordsCompanion.insert(
                accountKey: accountKey,
                id: id,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TodoListRecordsTable, TodoListRecord>(table),
                  BaseReferences<
                    _$TodoDatabase,
                    $TodoListRecordsTable,
                    TodoListRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodoListRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TodoDatabase,
      $TodoListRecordsTable,
      TodoListRecord,
      $$TodoListRecordsTableFilterComposer,
      $$TodoListRecordsTableOrderingComposer,
      $$TodoListRecordsTableAnnotationComposer,
      $$TodoListRecordsTableCreateCompanionBuilder,
      $$TodoListRecordsTableUpdateCompanionBuilder,
      (
        TodoListRecord,
        BaseReferences<_$TodoDatabase, $TodoListRecordsTable, TodoListRecord>,
      ),
      TodoListRecord,
      PrefetchHooks Function()
    >;
typedef $$ListGroupRecordsTableCreateCompanionBuilder =
    ListGroupRecordsCompanion Function({
      required String accountKey,
      required String id,
      required int position,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$ListGroupRecordsTableUpdateCompanionBuilder =
    ListGroupRecordsCompanion Function({
      Value<String> accountKey,
      Value<String> id,
      Value<int> position,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$ListGroupRecordsTableFilterComposer
    extends Composer<_$TodoDatabase, $ListGroupRecordsTable> {
  $$ListGroupRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ListGroupRecordsTableOrderingComposer
    extends Composer<_$TodoDatabase, $ListGroupRecordsTable> {
  $$ListGroupRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ListGroupRecordsTableAnnotationComposer
    extends Composer<_$TodoDatabase, $ListGroupRecordsTable> {
  $$ListGroupRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$ListGroupRecordsTableTableManager
    extends
        RootTableManager<
          _$TodoDatabase,
          $ListGroupRecordsTable,
          ListGroupRecord,
          $$ListGroupRecordsTableFilterComposer,
          $$ListGroupRecordsTableOrderingComposer,
          $$ListGroupRecordsTableAnnotationComposer,
          $$ListGroupRecordsTableCreateCompanionBuilder,
          $$ListGroupRecordsTableUpdateCompanionBuilder,
          (
            ListGroupRecord,
            BaseReferences<
              _$TodoDatabase,
              $ListGroupRecordsTable,
              ListGroupRecord
            >,
          ),
          ListGroupRecord,
          PrefetchHooks Function()
        > {
  $$ListGroupRecordsTableTableManager(
    _$TodoDatabase db,
    $ListGroupRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListGroupRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListGroupRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListGroupRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ListGroupRecordsCompanion(
                accountKey: accountKey,
                id: id,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String id,
                required int position,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => ListGroupRecordsCompanion.insert(
                accountKey: accountKey,
                id: id,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ListGroupRecordsTable, ListGroupRecord>(table),
                  BaseReferences<
                    _$TodoDatabase,
                    $ListGroupRecordsTable,
                    ListGroupRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ListGroupRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TodoDatabase,
      $ListGroupRecordsTable,
      ListGroupRecord,
      $$ListGroupRecordsTableFilterComposer,
      $$ListGroupRecordsTableOrderingComposer,
      $$ListGroupRecordsTableAnnotationComposer,
      $$ListGroupRecordsTableCreateCompanionBuilder,
      $$ListGroupRecordsTableUpdateCompanionBuilder,
      (
        ListGroupRecord,
        BaseReferences<_$TodoDatabase, $ListGroupRecordsTable, ListGroupRecord>,
      ),
      ListGroupRecord,
      PrefetchHooks Function()
    >;
typedef $$TaskItemRecordsTableCreateCompanionBuilder =
    TaskItemRecordsCompanion Function({
      required String accountKey,
      required String id,
      required String listId,
      required int position,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$TaskItemRecordsTableUpdateCompanionBuilder =
    TaskItemRecordsCompanion Function({
      Value<String> accountKey,
      Value<String> id,
      Value<String> listId,
      Value<int> position,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$TaskItemRecordsTableFilterComposer
    extends Composer<_$TodoDatabase, $TaskItemRecordsTable> {
  $$TaskItemRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskItemRecordsTableOrderingComposer
    extends Composer<_$TodoDatabase, $TaskItemRecordsTable> {
  $$TaskItemRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskItemRecordsTableAnnotationComposer
    extends Composer<_$TodoDatabase, $TaskItemRecordsTable> {
  $$TaskItemRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get listId =>
      $composableBuilder(column: $table.listId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$TaskItemRecordsTableTableManager
    extends
        RootTableManager<
          _$TodoDatabase,
          $TaskItemRecordsTable,
          TaskItemRecord,
          $$TaskItemRecordsTableFilterComposer,
          $$TaskItemRecordsTableOrderingComposer,
          $$TaskItemRecordsTableAnnotationComposer,
          $$TaskItemRecordsTableCreateCompanionBuilder,
          $$TaskItemRecordsTableUpdateCompanionBuilder,
          (
            TaskItemRecord,
            BaseReferences<
              _$TodoDatabase,
              $TaskItemRecordsTable,
              TaskItemRecord
            >,
          ),
          TaskItemRecord,
          PrefetchHooks Function()
        > {
  $$TaskItemRecordsTableTableManager(
    _$TodoDatabase db,
    $TaskItemRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskItemRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskItemRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskItemRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> listId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskItemRecordsCompanion(
                accountKey: accountKey,
                id: id,
                listId: listId,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String id,
                required String listId,
                required int position,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => TaskItemRecordsCompanion.insert(
                accountKey: accountKey,
                id: id,
                listId: listId,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaskItemRecordsTable, TaskItemRecord>(table),
                  BaseReferences<
                    _$TodoDatabase,
                    $TaskItemRecordsTable,
                    TaskItemRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskItemRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TodoDatabase,
      $TaskItemRecordsTable,
      TaskItemRecord,
      $$TaskItemRecordsTableFilterComposer,
      $$TaskItemRecordsTableOrderingComposer,
      $$TaskItemRecordsTableAnnotationComposer,
      $$TaskItemRecordsTableCreateCompanionBuilder,
      $$TaskItemRecordsTableUpdateCompanionBuilder,
      (
        TaskItemRecord,
        BaseReferences<_$TodoDatabase, $TaskItemRecordsTable, TaskItemRecord>,
      ),
      TaskItemRecord,
      PrefetchHooks Function()
    >;
typedef $$SyncMutationRecordsTableCreateCompanionBuilder =
    SyncMutationRecordsCompanion Function({
      required String accountKey,
      required String kind,
      required String itemKey,
      required int position,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$SyncMutationRecordsTableUpdateCompanionBuilder =
    SyncMutationRecordsCompanion Function({
      Value<String> accountKey,
      Value<String> kind,
      Value<String> itemKey,
      Value<int> position,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$SyncMutationRecordsTableFilterComposer
    extends Composer<_$TodoDatabase, $SyncMutationRecordsTable> {
  $$SyncMutationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMutationRecordsTableOrderingComposer
    extends Composer<_$TodoDatabase, $SyncMutationRecordsTable> {
  $$SyncMutationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMutationRecordsTableAnnotationComposer
    extends Composer<_$TodoDatabase, $SyncMutationRecordsTable> {
  $$SyncMutationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$SyncMutationRecordsTableTableManager
    extends
        RootTableManager<
          _$TodoDatabase,
          $SyncMutationRecordsTable,
          SyncMutationRecord,
          $$SyncMutationRecordsTableFilterComposer,
          $$SyncMutationRecordsTableOrderingComposer,
          $$SyncMutationRecordsTableAnnotationComposer,
          $$SyncMutationRecordsTableCreateCompanionBuilder,
          $$SyncMutationRecordsTableUpdateCompanionBuilder,
          (
            SyncMutationRecord,
            BaseReferences<
              _$TodoDatabase,
              $SyncMutationRecordsTable,
              SyncMutationRecord
            >,
          ),
          SyncMutationRecord,
          PrefetchHooks Function()
        > {
  $$SyncMutationRecordsTableTableManager(
    _$TodoDatabase db,
    $SyncMutationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMutationRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMutationRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SyncMutationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMutationRecordsCompanion(
                accountKey: accountKey,
                kind: kind,
                itemKey: itemKey,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String kind,
                required String itemKey,
                required int position,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: kind,
                itemKey: itemKey,
                position: position,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMutationRecordsTable, SyncMutationRecord>(
                    table,
                  ),
                  BaseReferences<
                    _$TodoDatabase,
                    $SyncMutationRecordsTable,
                    SyncMutationRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMutationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TodoDatabase,
      $SyncMutationRecordsTable,
      SyncMutationRecord,
      $$SyncMutationRecordsTableFilterComposer,
      $$SyncMutationRecordsTableOrderingComposer,
      $$SyncMutationRecordsTableAnnotationComposer,
      $$SyncMutationRecordsTableCreateCompanionBuilder,
      $$SyncMutationRecordsTableUpdateCompanionBuilder,
      (
        SyncMutationRecord,
        BaseReferences<
          _$TodoDatabase,
          $SyncMutationRecordsTable,
          SyncMutationRecord
        >,
      ),
      SyncMutationRecord,
      PrefetchHooks Function()
    >;

class $TodoDatabaseManager {
  final _$TodoDatabase _db;
  $TodoDatabaseManager(this._db);
  $$TodoListRecordsTableTableManager get todoListRecords =>
      $$TodoListRecordsTableTableManager(_db, _db.todoListRecords);
  $$ListGroupRecordsTableTableManager get listGroupRecords =>
      $$ListGroupRecordsTableTableManager(_db, _db.listGroupRecords);
  $$TaskItemRecordsTableTableManager get taskItemRecords =>
      $$TaskItemRecordsTableTableManager(_db, _db.taskItemRecords);
  $$SyncMutationRecordsTableTableManager get syncMutationRecords =>
      $$SyncMutationRecordsTableTableManager(_db, _db.syncMutationRecords);
}
