import 'package:flutter/material.dart';
import 'database.dart';
import 'scanner_screen.dart';
import 'delete_dialog.dart';

class InventoryScreen extends StatefulWidget {
  final String? selectedDate;
  final VoidCallback? onRefresh;

  const InventoryScreen({super.key, this.selectedDate, this.onRefresh});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _items = [];
  List<InventoryItem> _filtered = [];
  final _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = widget.selectedDate != null
        ? await DatabaseHelper.instance.getItemsByDate(widget.selectedDate!)
        : await DatabaseHelper.instance.getAllItems();
    setState(() {
      _items = items;
      _filtered = items;
      _loading = false;
    });
    _search(_searchController.text);
  }

  void _search(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? _items
          : _items
              .where((item) =>
                  item.productName
                      .toLowerCase()
                      .contains(query.toLowerCase()) ||
                  (item.serial
                          ?.toLowerCase()
                          .contains(query.toLowerCase()) ??
                      false) ||
                  item.warehouseName
                      .toLowerCase()
                      .contains(query.toLowerCase()))
              .toList();
    });
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final deleted = await showDeleteWithReasonDialog(context, item);
    if (deleted) {
      _loadItems();
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف "${item.productName}" وتسجيله في السجل'),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: 'سجل الحذف',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  Color _conditionColor(String condition) {
    switch (condition) {
      case 'جديد':
        return Colors.green;
      case 'مستخدم':
        return Colors.orange;
      case 'تالف':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        })
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(children: [
              Text('${_filtered.length} قطعة',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('لا توجد عناصر',
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 16)),
                          ]),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadItems,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final item = _filtered[i];
                            final condColor =
                                _conditionColor(item.condition);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(14),
                                onTap: () async {
                                  final result =
                                      await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => AddItemScreen(
                                            itemToEdit: item)),
                                  );
                                  if (result == true) {
                                    _loadItems();
                                    widget.onRefresh?.call();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 56,
                                        decoration: BoxDecoration(
                                            color: condColor,
                                            borderRadius:
                                                BorderRadius.circular(
                                                    4)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(item.productName,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 14)),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              Icon(Icons.warehouse,
                                                  size: 12,
                                                  color: Colors
                                                      .grey.shade500),
                                              const SizedBox(width: 3),
                                              Expanded(
                                                  child: Text(
                                                item.warehouseName,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors
                                                        .grey.shade600),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              )),
                                            ]),
                                            if (item.serial != null)
                                              Row(children: [
                                                Icon(Icons.qr_code,
                                                    size: 12,
                                                    color: Colors
                                                        .grey.shade500),
                                                const SizedBox(width: 3),
                                                Text(item.serial!,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey
                                                            .shade600)),
                                              ]),
                                            if (item.expiryDate != null &&
                                                item.expiryDate!.isNotEmpty)
                                              Row(children: [
                                                Icon(Icons.event,
                                                    size: 12,
                                                    color: Colors
                                                        .grey.shade500),
                                                const SizedBox(width: 3),
                                                Text(
                                                    'صلاحية: ${item.expiryDate}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey
                                                            .shade600)),
                                              ]),
                                            if (item.notes != null &&
                                                item.notes!.isNotEmpty)
                                              Row(children: [
                                                Icon(Icons.notes,
                                                    size: 12,
                                                    color: Colors
                                                        .grey.shade500),
                                                const SizedBox(width: 3),
                                                Expanded(
                                                    child: Text(
                                                  item.notes!,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .grey.shade600),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                )),
                                              ]),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4),
                                            decoration: BoxDecoration(
                                              color: condColor
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(item.condition,
                                                style: TextStyle(
                                                    color: condColor,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12)),
                                          ),
                                          const SizedBox(height: 8),
                                          GestureDetector(
                                            onTap: () =>
                                                _deleteItem(item),
                                            child: Icon(
                                                Icons.delete_outline,
                                                color:
                                                    Colors.red.shade300,
                                                size: 20),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}