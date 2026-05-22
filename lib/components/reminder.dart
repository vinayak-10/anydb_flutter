import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/gen_interface.dart';

class Reminder extends GenInterface {
  String name = '';
  String id = '';
  Map<String, dynamic> defaultValue = {};
  DateTime? value;
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => 'reminder';

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
    name = jsonObj['name'] ?? '';
    id = jsonObj['id']?.toString() ?? '';
    defaultValue = jsonObj['defaultValue'] ?? {'year': '0', 'month': '0', 'days': '30'};
    value = _getNextDate(defaultValue, DateTime.now());
  }

  @override
  GenInterface clone() {
    final c = Reminder();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  DateTime _getNextDate(Map<String, dynamic> val, DateTime from) {
    int days = int.tryParse(val['days']?.toString() ?? '0') ?? 0;
    int months = int.tryParse(val['month']?.toString() ?? '0') ?? 0;
    int years = int.tryParse(val['year']?.toString() ?? '0') ?? 0;

    return DateTime(
      from.year + years,
      from.month + months,
      from.day + days,
    );
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      value = DateTime.fromMillisecondsSinceEpoch(jsonDb[name]);
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: value?.millisecondsSinceEpoch ?? 0};
  }

  bool isExpired() {
    if (value == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Expired if value is today or before
    return value!.isBefore(today) || (value!.day == today.day && value!.month == today.month && value!.year == today.year);
  }

  String getRelativeTime() {
    if (value == null) return "";
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final valDay = DateTime(value!.year, value!.month, value!.day);
    final diff = valDay.difference(today).inDays;
    
    if (diff == 0) return "due today";
    if (diff == 1) return "due tomorrow";
    if (diff > 1) return "in $diff days";
    if (diff == -1) return "expired yesterday";
    return "expired ${diff.abs()} days ago";
  }

  @override
  Widget editor({required Key key, required Function(dynamic) onChanged, Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent, dynamic frefs, int? index, bool? autoFocus, bool? refresh}) {
    return _ReminderEditor(
      key: key,
      reminder: this,
      onChanged: onChanged,
    );
  }

  @override
  Widget display({bool onlyValue = false, List<dynamic>? displayComponent, VoidCallback? onChanged}) {
    final expired = isExpired();
    final color = expired ? Colors.red : Colors.green;
    final text = "${getRelativeTime()} on ${value != null ? DateFormat('E, MMM d').format(value!) : ''}";
    
    if (onlyValue) return Text(text, style: TextStyle(color: color, fontSize: 12));
    
    return Row(
      children: [
        Text("$name: ", style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }

  @override
  Widget? invoke({required String method, required Map<String, dynamic> parameters, VoidCallback? onChanged}) {
    if (method == 'text') {
      final expired = isExpired();
      final color = expired ? Colors.red : Colors.green;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "${getRelativeTime()} on ${value != null ? DateFormat('MMM d').format(value!) : ''}",
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold), // Increased size +3
          ),
          if (expired) 
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: TextButton(
                onPressed: () {
                  value = _getNextDate(defaultValue, DateTime.now());
                  if (onChanged != null) onChanged();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.shade100, // Turned Red as requested
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  minimumSize: const Size(0, 36), // Increased size
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("RESET", style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)), // Size +3
              ),
            ),
        ],
      );
    }
    return null;
  }
}

class _ReminderEditor extends StatefulWidget {
  final Reminder reminder;
  final Function(dynamic) onChanged;

  const _ReminderEditor({super.key, required this.reminder, required this.onChanged});

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final expired = widget.reminder.isExpired();
    final color = expired ? Colors.red : Colors.green;
    final dateStr = widget.reminder.value != null ? DateFormat('E, MMM d').format(widget.reminder.value!) : '';
    final titleText = "${widget.reminder.name} ${expired ? "Expired" : ""} ${widget.reminder.getRelativeTime()} on $dateStr";

    if (!expanded) {
      return ElevatedButton(
        onPressed: () => setState(() => expanded = true),
        child: Text(titleText, style: TextStyle(color: color)),
      );
    }

    return Card(
      elevation: 5,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(titleText, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text("Remind after", style: TextStyle(color: Colors.orange)),
            ),
            Row(
              children: [
                Expanded(child: TextFormField(
                  initialValue: widget.reminder.defaultValue['days']?.toString(),
                  decoration: const InputDecoration(labelText: "Days", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    widget.reminder.defaultValue['days'] = val;
                    setState(() {
                      widget.reminder.value = widget.reminder._getNextDate(widget.reminder.defaultValue, DateTime.now());
                    });
                    widget.onChanged(null);
                  },
                )),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(
                  initialValue: widget.reminder.defaultValue['month']?.toString(),
                  decoration: const InputDecoration(labelText: "Months", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    widget.reminder.defaultValue['month'] = val;
                    setState(() {
                      widget.reminder.value = widget.reminder._getNextDate(widget.reminder.defaultValue, DateTime.now());
                    });
                    widget.onChanged(null);
                  },
                )),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => expanded = false),
              child: const Text("DONE"),
            )
          ],
        ),
      ),
    );
  }
}
