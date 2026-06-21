import 'package:flutter/material.dart';

abstract class GenInterface {
  static int smObjId = 0;

  GenInterface() {
    smObjId++;
  }

  String getType();

  void init(Map<String, dynamic> jsonObj, dynamic repoIntf);

  GenInterface? clone();

  void populate(Map<String, dynamic> jsonDb);

  Map<String, dynamic> fetch();

  Map<String, dynamic> validate() {
    return {'valid': true, 'name': '', 'constraint': ''};
  }

  List<bool> match(String val, {bool exact = false}) {
    return [false, false];
  }

  bool event(String what, Map<String, dynamic> jo) {
    return false;
  }

  String getId() {
    return "";
  }

  String getName() {
    return "";
  }

  GenInterface getComponent(String key) {
    return this;
  }

  GenInterface? getComponentAtIndex(int index) {
    return null;
  }

  int getComponentIdIndex(String id) {
    return -1;
  }

  String getValue() {
    return "";
  }

  Widget editor({
    required Key key,
    required Function(dynamic) onChanged,
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs,
    int? index,
    bool? autoFocus,
    bool? refresh,
  }) {
    return const SizedBox.shrink();
  }

  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    return const SizedBox.shrink();
  }

  Widget? invoke({
    required String method,
    required Map<String, dynamic> parameters,
    VoidCallback? onChanged,
  }) {
    return null;
  }

  Map<String, dynamic> get() {
    return {"Unknown": "Undefined"};
  }

  bool notify(dynamic d) {
    return false;
  }

  List<dynamic> getObservers() {
    return [];
  }

  void set(Map<String, dynamic> jo) {}
}
