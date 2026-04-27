import 'dart:io';

void main() {
  final dir = Directory('lib/db');
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.contains('database_sync') || file.path.contains('database_helper') || file.path.contains('inject_hook')) continue;
    String content = file.readAsStringSync();
    
    content = content.replaceAll("await txn.insert(", "_notifyChanged(); await txn.insert(");
    content = content.replaceAll("await txn.update(", "_notifyChanged(); await txn.update(");
    content = content.replaceAll("await txn.delete(", "_notifyChanged(); await txn.delete(");
    content = content.replaceAll("await executor.insert(", "_notifyChanged(); await executor.insert(");
    content = content.replaceAll("await executor.update(", "_notifyChanged(); await executor.update(");
    content = content.replaceAll("await executor.delete(", "_notifyChanged(); await executor.delete(");
    content = content.replaceAll("await db.insert(", "_notifyChanged(); await db.insert(");
    content = content.replaceAll("await db.update(", "_notifyChanged(); await db.update(");
    content = content.replaceAll("await db.delete(", "_notifyChanged(); await db.delete(");
    
    content = content.replaceAll("return txn.update(", "_notifyChanged(); return txn.update(");
    content = content.replaceAll("return txn.insert(", "_notifyChanged(); return txn.insert(");
    content = content.replaceAll("return db.update(", "_notifyChanged(); return db.update(");
    content = content.replaceAll("return db.insert(", "_notifyChanged(); return db.insert(");
    content = content.replaceAll("return executor.update(", "_notifyChanged(); return executor.update(");
    content = content.replaceAll("return executor.insert(", "_notifyChanged(); return executor.insert(");
    
    file.writeAsStringSync(content);
  }
}
