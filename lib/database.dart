import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class InventoryItem {
  final int? id;
  final String warehouseName;
  final String productName;
  final String? serial;
  final String condition;
  final String? expiryDate;
  final String? notes;
  final String inventoryDate;
  final String? addedByUid; // ✅ جديد: مين أضاف القطعة

  InventoryItem({
    this.id,
    required this.warehouseName,
    required this.productName,
    this.serial,
    required this.condition,
    this.expiryDate,
    this.notes,
    String? inventoryDate,
    this.addedByUid,
  }) : inventoryDate = inventoryDate ?? today();

  static String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'warehouse_name': warehouseName,
      'product_name': productName,
      'serial': serial,
      'condition': condition,
      'expiry_date': expiryDate,
      'notes': notes,
      'inventory_date': inventoryDate,
      'added_by_uid': addedByUid,
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'],
      warehouseName: map['warehouse_name'],
      productName: map['product_name'],
      serial: map['serial'],
      condition: map['condition'],
      expiryDate: map['expiry_date'],
      notes: map['notes'],
      inventoryDate: map['inventory_date'] ?? today(),
      addedByUid: map['added_by_uid'],
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('inventory.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 4, // ✅ رفعنا الـ version
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_name TEXT NOT NULL,
        product_name TEXT NOT NULL,
        serial TEXT,
        condition TEXT NOT NULL,
        expiry_date TEXT,
        notes TEXT,
        inventory_date TEXT NOT NULL,
        added_by_uid TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE deleted_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_name TEXT,
        product_name TEXT,
        serial TEXT,
        condition TEXT,
        expiry_date TEXT,
        notes TEXT,
        inventory_date TEXT,
        delete_reason TEXT,
        delete_notes TEXT,
        deleted_at TEXT,
        deleted_by_uid TEXT,
        added_by_uid TEXT
      )
    ''');
    await _insertDefaultData(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE inventory ADD COLUMN notes TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE inventory ADD COLUMN inventory_date TEXT');
      } catch (_) {}
      await db.rawUpdate(
          "UPDATE inventory SET inventory_date = '${InventoryItem.today()}' WHERE inventory_date IS NULL");
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          warehouse_name TEXT,
          product_name TEXT,
          serial TEXT,
          condition TEXT,
          expiry_date TEXT,
          notes TEXT,
          inventory_date TEXT,
          delete_reason TEXT,
          delete_notes TEXT,
          deleted_at TEXT
        )
      ''');
      await db.insert('warehouses', {'name': 'WH32/Stock 1'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 4) {
      // ✅ إضافة حقل مين أضاف وحقل مين حذف
      try {
        await db.execute(
            'ALTER TABLE inventory ADD COLUMN added_by_uid TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE deleted_items ADD COLUMN deleted_by_uid TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE deleted_items ADD COLUMN added_by_uid TEXT');
      } catch (_) {}
    }
  }

  Future _insertDefaultData(Database db) async {
    await db.insert('warehouses', {'name': 'WH32/Stock 1'});
    final products = [
      'Mismon/جهاز مس مون',
      'جهاز مليسة الإصدار الخامس',
      'جهاز مليسة الإصدار السادس',
      'WETRACK 2/جهاز تتبع صينى',
      'SMART CARD',
      'SIM CARD',
      'بيردي دي في ار / Birdie DVR - 3 CAM',
      'بيردي دي في ار / Birdie DVR - 2 CAM',
      '(GIFT - BOX)/صندوق الهدايا',
      'AC - M4/عدسة حب الشباب الاصدار الرابع',
      'AC - M5/عدسة حب الشباب الاصدار الخامس',
      'AC - M6/عدسة حب الشباب الاصدار السادس',
      'Alfacort / Betaderm',
      'BIKINI - HR-M6/عدسة المناطق الحساسة الاصدار السادس',
      'BIKINI - HR/عدسة المناطق الحساسة',
      'BURNS CREAM',
      'FACE - HR-M6/عدسة الوجه الإصدار السادس',
      'HR - M4/عدسة الجسم الإصدار الرابع',
      'HR - M5/عدسة الجسم الإصدار الخامس',
      'HR - M5_2/عدسة الجسم الإصدار الخامس -٢',
      'HR - M6/عدسة الجسم الإصدار السادس',
      'HR - TEST/عدسة الجسم-اختبار',
      'man lamp/عدسة الرجال',
      'Mis ac/عدسة مس مون لحب الشباب',
      'Mis -Bhr/عدسة مس مون للمناطق الحساسة',
      'Mis -FHR/عدسة مس مون للوجه',
      'Mis hr/عدسة مس مون للجسم',
      'Mis sr/عدسة مس مون للنضارة',
      'mis-hr test/عدسة مس مون للجسم -اختبار',
      'SR - M4/عدسة نضارة الاصدار الرابع',
      'SR - M5/عدسة نضارة الإصدار الخامس',
      'SR - M6/عدسة نضارة الإصدار السادس',
      'Charger',
      'سجادة صلاة',
      'كريم مرطب افالون',
      'GPS TRACKING - جهاز تتبع',
    ];
    for (final p in products) {
      await db.insert('products', {'name': p},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ============================================================
  // Inventory CRUD
  // ============================================================

  Future<int> insertItem(InventoryItem item) async {
    final db = await database;
    final id = await db.insert('inventory', item.toMap());
    await addWarehouse(item.warehouseName);
    await addProduct(item.productName);
    return id;
  }

  Future<List<InventoryItem>> getAllItems() async {
    final db = await database;
    final result = await db.query('inventory',
        orderBy: 'inventory_date DESC, id DESC');
    return result.map((map) => InventoryItem.fromMap(map)).toList();
  }

  Future<List<InventoryItem>> getItemsByDate(String date) async {
    final db = await database;
    final result = await db.query('inventory',
        where: 'inventory_date = ?',
        whereArgs: [date],
        orderBy: 'id DESC');
    return result.map((map) => InventoryItem.fromMap(map)).toList();
  }

  // ✅ جديد: جيب القطع الخاصة بـ user معين في مخزن معين
  Future<List<InventoryItem>> getItemsByUserAndWarehouse({
    required String uid,
    required String warehouseName,
    String? date,
  }) async {
    final db = await database;
    String where = 'added_by_uid = ? AND warehouse_name = ?';
    List<dynamic> args = [uid, warehouseName];
    if (date != null) {
      where += ' AND inventory_date = ?';
      args.add(date);
    }
    final result = await db.query(
      'inventory',
      where: where,
      whereArgs: args,
      orderBy: 'inventory_date DESC, id DESC',
    );
    return result.map((map) => InventoryItem.fromMap(map)).toList();
  }

  // ✅ جديد: إحصائيات مخصصة لـ user
  Future<Map<String, int>> getStatsByUser({
    required String uid,
    required String warehouseName,
    String? date,
  }) async {
    final db = await database;
    String baseWhere = "added_by_uid='$uid' AND warehouse_name='$warehouseName'";
    if (date != null) baseWhere += " AND inventory_date='$date'";

    final total = Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM inventory WHERE $baseWhere')) ??
        0;
    final good = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE $baseWhere AND condition='جديد'")) ??
        0;
    final used = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE $baseWhere AND condition='مستخدم'")) ??
        0;
    final damaged = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE $baseWhere AND condition='تالف'")) ??
        0;
    final deleted = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM deleted_items WHERE deleted_by_uid='$uid'")) ??
        0;
    return {
      'total': total,
      'good': good,
      'used': used,
      'damaged': damaged,
      'deleted': deleted,
    };
  }

  Future<List<String>> getInventoryDates() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT DISTINCT inventory_date FROM inventory ORDER BY inventory_date DESC');
    return result.map((r) => r['inventory_date'] as String).toList();
  }

  // ✅ جديد: تواريخ الجرد الخاصة بـ user في مخزن معين
  Future<List<String>> getInventoryDatesByUser({
    required String uid,
    required String warehouseName,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT DISTINCT inventory_date FROM inventory WHERE added_by_uid='$uid' AND warehouse_name='$warehouseName' ORDER BY inventory_date DESC");
    return result.map((r) => r['inventory_date'] as String).toList();
  }

  Future<int> updateItem(InventoryItem item) async {
    final db = await database;
    return db.update('inventory', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  // ✅ جديد: نقل قطعة من مخزن لمخزن (Admin فقط)
  Future<void> moveItemToWarehouse(int itemId, String newWarehouse) async {
    final db = await database;
    await db.update(
      'inventory',
      {'warehouse_name': newWarehouse},
      where: 'id = ?',
      whereArgs: [itemId],
    );
    await addWarehouse(newWarehouse);
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return db.delete('inventory', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> deleteWithReason(
    InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? deletedByUid,
  }) async {
    final db = await database;
    await db.insert('deleted_items', {
      'warehouse_name': item.warehouseName,
      'product_name': item.productName,
      'serial': item.serial,
      'condition': item.condition,
      'expiry_date': item.expiryDate,
      'notes': item.notes,
      'inventory_date': item.inventoryDate,
      'delete_reason': reason,
      'delete_notes': extraNotes ?? '',
      'deleted_at': DateTime.now().toIso8601String(),
      'deleted_by_uid': deletedByUid,
      'added_by_uid': item.addedByUid,
    });
    if (item.id != null) {
      await db.delete('inventory',
          where: 'id = ?', whereArgs: [item.id]);
    }
    return true;
  }

  // ============================================================
  // Deleted Items
  // ============================================================

  Future<List<Map<String, dynamic>>> getDeletedItems() async {
    final db = await database;
    return db.query('deleted_items', orderBy: 'deleted_at DESC');
  }

  // ✅ جديد: سجل حذف الـ user بس (اللي هو حذفه)
  Future<List<Map<String, dynamic>>> getDeletedItemsByUser(
      String uid) async {
    final db = await database;
    return db.query(
      'deleted_items',
      where: 'deleted_by_uid = ?',
      whereArgs: [uid],
      orderBy: 'deleted_at DESC',
    );
  }

  Future<void> restoreItem(Map<String, dynamic> deletedItem) async {
    final db = await database;
    await db.insert('inventory', {
      'warehouse_name': deletedItem['warehouse_name'],
      'product_name': deletedItem['product_name'],
      'serial': deletedItem['serial'],
      'condition': deletedItem['condition'],
      'expiry_date': deletedItem['expiry_date'],
      'notes': 'مستعاد - ${deletedItem['delete_reason'] ?? ''}',
      'inventory_date':
          deletedItem['inventory_date'] ?? InventoryItem.today(),
      'added_by_uid': deletedItem['added_by_uid'],
    });
    // يحدّث السجل بوقت الاستعادة بس مش بيحذفه
    await db.update(
      'deleted_items',
      {
        'delete_notes':
            '${deletedItem['delete_notes'] ?? ''} | مستعاد: ${DateTime.now().toString().substring(0, 16)}'
      },
      where: 'id = ?',
      whereArgs: [deletedItem['id']],
    );
  }

  Future<void> permanentDeleteItem(int id) async {
    final db = await database;
    await db.delete('deleted_items', where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // Warehouses & Products
  // ============================================================

  Future<void> addWarehouse(String name) async {
    final db = await database;
    await db.insert('warehouses', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> getWarehouses() async {
    final db = await database;
    final result = await db.query('warehouses', orderBy: 'name');
    return result.map((r) => r['name'] as String).toList();
  }

  Future<void> addProduct(String name) async {
    final db = await database;
    await db.insert('products', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> getProducts() async {
    final db = await database;
    final result = await db.query('products', orderBy: 'name');
    return result.map((r) => r['name'] as String).toList();
  }

  // ============================================================
  // Stats
  // ============================================================

  Future<Map<String, int>> getStats({String? date}) async {
    final db = await database;
    final w = date != null ? "WHERE inventory_date='$date'" : '';
    final aw = date != null ? "AND inventory_date='$date'" : '';
    final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM inventory $w')) ??
        0;
    final good = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE condition='جديد' $aw")) ??
        0;
    final used = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE condition='مستخدم' $aw")) ??
        0;
    final damaged = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inventory WHERE condition='تالف' $aw")) ??
        0;
    final deleted = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM deleted_items')) ??
        0;
    return {
      'total': total,
      'good': good,
      'used': used,
      'damaged': damaged,
      'deleted': deleted,
    };
  }
}