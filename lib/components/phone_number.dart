import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/gen_interface.dart';
import '../services/invoker_service.dart';
import '../core/settings_provider.dart';

class PhoneNumber extends GenInterface {
  String name = "";
  String id = "";
  String value = "";
  bool searchable = false;
  List<dynamic> observers = [];
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "phoneNumber";

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    value = jsonObj['defaultValue'] ?? "";
    searchable = jsonObj['searchable'] ?? false;
    observers = jsonObj['observers'] is List ? jsonObj['observers'] : [];
  }

  @override
  GenInterface clone() {
    final c = PhoneNumber();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  List<dynamic> getObservers() => observers;

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      value = jsonDb[name]?.toString() ?? "";
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: value};
  }

  @override
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      if (exact) {
        if (value == val) return [true, true];
      } else {
        if (value == val) return [true, true];
        if (value.contains(val)) return [true, false];
      }
    }
    return [false, false];
  }

  @override
  Widget editor({
    required Key key, 
    required Function(dynamic) onChanged, 
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs, 
    int? index, 
    bool? autoFocus, 
    bool? refresh
  }) {
    return _PhoneNumberEditor(
      key: key,
      label: name,
      initialValue: value,
      onChanged: (txt) {
        value = txt;
        onChanged(txt);
        if (cbNotifyParent != null) {
          cbNotifyParent(this, {name: txt}, observers);
        }
      },
    );
  }

  @override
  Widget display({bool onlyValue = false, List<dynamic>? displayComponent, VoidCallback? onChanged}) {
    if (onlyValue) return Text(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            children: [
              _IconButton(
                icon: Icons.phone,
                color: Colors.teal,
                onPressed: () => InvokerService.call(value),
              ),
              const SizedBox(width: 16),
              _IconButton(
                icon: Icons.message,
                color: Colors.orange,
                onPressed: () => InvokerService.text(value),
              ),
              const SizedBox(width: 16),
              _IconButton(
                icon: Icons.chat, // WhatsApp placeholder
                color: Colors.green,
                onPressed: () => InvokerService.whatsapp(value),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: color,
      radius: 20,
      child: IconButton(
        icon: Icon(icon, size: 20, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

class _PhoneNumberEditor extends StatefulWidget {
  final String label;
  final String initialValue;
  final Function(String) onChanged;

  const _PhoneNumberEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_PhoneNumberEditor> createState() => _PhoneNumberEditorState();
}

class _PhoneNumberEditorState extends State<_PhoneNumberEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final settings = ref.watch(settingsProvider);
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: settings.inputFontSize),
            decoration: InputDecoration(
              labelText: widget.label,
              filled: true,
              fillColor: Colors.grey[100],
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        );
      },
    );
  }
}
