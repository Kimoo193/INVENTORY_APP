import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'inventory_repository.dart';
import 'app_localizations.dart';

// ── Delete With Reason ────────────────────────────────────────
// Uses BottomSheet instead of AlertDialog to avoid the
// GridView-inside-SingleChildScrollView-inside-AlertDialog
// intrinsic-dimensions crash that freezes the app.
Future<bool> showDeleteWithReasonDialog(
    BuildContext context, InventoryItem item) async {
  final isAr = AppLocalizations.isArabic;

  final reasons = isAr
      ? ['مباع', 'تالف/عاطل', 'مرتجع', 'نقل لمخزن آخر', 'خطأ في الإدخال', 'أخرى']
      : ['Sold', 'Damaged', 'Returned', 'Transferred', 'Entry Error', 'Other'];

  String selectedReason = reasons.first;
  final notesController = TextEditingController();

  final confirm = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'سبب الحذف' : 'Delete Reason',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          item.productName,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),

              if (item.serial != null && item.serial!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.qr_code_2_rounded,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(item.serial!,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontFamily: 'monospace')),
                    ]),
                  ),
                ),

              // Section label
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    isAr ? 'اختر السبب:' : 'Select reason:',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.grey.shade700),
                  ),
                ),
              ),

              // Reason chips — 2 per row using plain Column+Row, NO GridView
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ReasonGrid(
                  reasons: reasons,
                  selected: selectedReason,
                  onSelect: (r) {
                    HapticFeedback.selectionClick();
                    set(() => selectedReason = r);
                  },
                ),
              ),

              // Notes field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'ملاحظة إضافية (اختياري)'
                        : 'Additional note (optional)',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF16324F), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  textDirection:
                      isAr ? TextDirection.rtl : TextDirection.ltr,
                  maxLines: 2,
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(isAr ? 'إلغاء' : 'Cancel',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18),
                      label: Text(
                          isAr ? 'تأكيد الحذف' : 'Confirm Delete',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  notesController.dispose();
  if (confirm != true) return false;

  final currentUser = await AuthService.instance.getCurrentUser();

  await InventoryRepository.instance.deleteWithReason(
    item,
    reason: selectedReason,
    extraNotes: notesController.text.trim(),
    deletedByUid: currentUser?.uid,
  );

  if (currentUser != null && !currentUser.isAdmin) {
    NotificationService.instance.notifyItemDeleted(
      productName: item.productName,
      reason: selectedReason,
      deletedByName: currentUser.name,
    );
  }

  return true;
}

// ── Reason chips grid — plain Rows, zero GridView ─────────────
class _ReasonGrid extends StatelessWidget {
  final List<String> reasons;
  final String selected;
  final void Function(String) onSelect;

  const _ReasonGrid({
    required this.reasons,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < reasons.length; i += 2) {
      rows.add(Row(
        children: [
          _chip(reasons[i]),
          const SizedBox(width: 8),
          if (i + 1 < reasons.length)
            _chip(reasons[i + 1])
          else
            const Expanded(child: SizedBox()),
        ],
      ));
      if (i + 2 < reasons.length) rows.add(const SizedBox(height: 8));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _chip(String r) {
    final isSel = selected == r;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF16324F) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel
                  ? const Color(0xFF16324F)
                  : Colors.grey.shade300,
            ),
          ),
          child: Center(
            child: Text(
              r,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSel ? Colors.white : Colors.black87,
                fontSize: 12,
                fontWeight:
                    isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}