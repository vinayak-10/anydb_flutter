import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/gen_interface.dart';

class DateTimeComponent extends GenInterface {
  String name = "";
  String id = "";
  DateTime value = DateTime.now();
  List<dynamic> observers = [];
  bool searchable = false;
  String mode = "date"; // "date" or "time" or "datetime"

  @override
  String getType() => "dateTime";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    value = jsonObj['defaultValue'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(jsonObj['defaultValue']) 
        : DateTime.now();
    observers = jsonObj['observers'] ?? [];
    searchable = jsonObj['searchable'] ?? false;
    mode = jsonObj['mode'] ?? "date";
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      final val = jsonDb[name];
      if (val is int) {
        value = DateTime.fromMillisecondsSinceEpoch(val);
      } else if (val is String) {
        value = DateTime.tryParse(val) ?? DateTime.now();
      }
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: value.millisecondsSinceEpoch};
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _DateTimeEditor(
      key: key,
      label: name,
      initialValue: value,
      mode: mode,
      onChanged: (dt) {
        value = dt;
        if (onChanged != null) onChanged(dt);
      },
    );
  }

  String getFormattedValue() {
    if (mode == "time") {
      return DateFormat.jm().format(value);
    } else if (mode == "datetime") {
      return DateFormat.yMMMMEEEEd().add_jm().format(value);
    }
    return DateFormat.yMMMMEEEEd().format(value);
  }

  @override
  Widget display({bool onlyValue = false}) {
    final displayValue = getFormattedValue();
    if (onlyValue) return Text(displayValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text("$name: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(displayValue),
        ],
      ),
    );
  }
}

class _DateTimeEditor extends StatefulWidget {
  final String label;
  final DateTime initialValue;
  final String mode;
  final Function(DateTime) onChanged;

  const _DateTimeEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.mode,
    required this.onChanged,
  });

  @override
  State<_DateTimeEditor> createState() => _DateTimeEditorState();
}

class _DateTimeEditorState extends State<_DateTimeEditor> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialValue;
  }

  Future<void> _pickDate() async {
    final localContext = context;
    if (widget.mode == "date" || widget.mode == "datetime") {
      final DateTime? picked = await showDatePicker(
        context: localContext,
        initialDate: _selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
      );
      if (picked != null && picked != _selectedDate) {
        setState(() {
          _selectedDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _selectedDate.hour,
            _selectedDate.minute,
          );
        });
        widget.onChanged(_selectedDate);
      }
    }
    
    if (!localContext.mounted) return;
    if (widget.mode == "time" || widget.mode == "datetime") {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: localContext,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
        widget.onChanged(_selectedDate);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String formatted = widget.mode == "time" 
        ? DateFormat.jm().format(_selectedDate)
        : DateFormat.yMMMMEEEEd().format(_selectedDate);
    
    if (widget.mode == "datetime") {
      formatted += " ${DateFormat.jm().format(_selectedDate)}";
    }

    return ListTile(
      title: Text(widget.label),
      subtitle: Text(formatted),
      trailing: const Icon(Icons.calendar_today),
      onTap: () => _pickDate(),
      tileColor: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
