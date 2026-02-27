import 'package:flutter/material.dart';
import 'database.dart';
import 'auth_service.dart';
import 'notification_service.dart';

Future<bool> showDeleteWithReasonDialog(
    BuildContext context, InventoryItem item) async {
  String selectedReason = 'مباع';
  final notesController = TextEditingController();
  final reasons = ['مباع','تالف/عاطل','مرتجع','نقل لمخزن آخر','خطأ في الإدخال','أخرى'];

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('سبب الحذف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (item.serial != null && item.serial!.isNotEmpty)
                  Text('S/N: ${item.serial}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 16),
                const Text('اختر السبب:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: reasons.map((r) {
                    final selected = selectedReason == r;
                    return GestureDetector(
                      onTap: () => setStateDialog(() => selectedReason = r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFF1A237E) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: selected ? const Color(0xFF1A237E) : Colors.grey.shade300),
                        ),
                        child: Text(r,
                            style: TextStyle(
                                color: selected ? Colors.white : Colors.black87,
                                fontSize: 13)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    hintText: 'ملاحظة إضافية (اختياري)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    ),
  );

  if (confirm != true) return false;

  final currentUser = await AuthService.instance.getCurrentUser();

  // ✅ حذف مع تسجيل مين حذف
  await DatabaseHelper.instance.deleteWithReason(
    item,
    reason: selectedReason,
    extraNotes: notesController.text.trim(),
    deletedByUid: currentUser?.uid,
  );

  // ✅ إشعار للـ Admins لو المستخدم مش Admin
  if (currentUser != null && !currentUser.isAdmin) {
    NotificationService.instance.notifyItemDeleted(
      productName: item.productName,
      reason: selectedReason,
      deletedByName: currentUser.name,
    );
  }

  return true;
}