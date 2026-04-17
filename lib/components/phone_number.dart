import 'package:flutter/material.dart';
import '../core/gen_interface.dart';
import '../services/invoker_service.dart';

class PhoneNumber extends GenInterface {
  String name = "";
  String id = "";
  String value = "";
  bool searchable = false;

  @override
  String getType() => "phoneNumber";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    value = jsonObj['defaultValue'] ?? "";
    searchable = jsonObj['searchable'] ?? false;
  }

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
  List<bool> match(String val) {
    if (searchable) {
      if (value == val) return [true, true];
      if (value.contains(val)) return [true, false];
    }
    return [false, false];
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _PhoneNumberEditor(
      key: key,
      label: name,
      initialValue: value,
      onChanged: (txt) {
        value = txt;
        if (onChanged != null) onChanged(txt);
      },
    );
  }

  @override
  Widget display({bool onlyValue = false}) {
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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: widget.label,
          filled: true,
          fillColor: Colors.grey[100],
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
