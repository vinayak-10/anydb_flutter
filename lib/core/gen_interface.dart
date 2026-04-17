import 'package:flutter/material.dart';

abstract class GenInterface {
  static int smObjId = 0;

  GenInterface() {
    smObjId++;
  }

  String getType() {
    return "undefined";
  }

  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    // this function take the json schema and initializes the object
  }

  GenInterface? clone() {
    return null;
  }

  void populate(Map<String, dynamic> jsonDb) {

  }

  Map<String, dynamic> fetch() {
    return {};
  }

  Map<String, dynamic> validate() {
    return {'name': '', 'valid': true, 'constraint': []};
  }

  List<bool> match(String val) {
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

  Widget editor({required Key key, Function? onChanged}) {
    // this is editor interface that is to be extended by derived class
    return const SizedBox.shrink();
  }

  Widget display({bool onlyValue = false}) {
    // this is display interface that is to be extended by derived class
    return const SizedBox.shrink();
  }

  Widget invoke(dynamic props) {
    // This function will return component that is invoked on object
    return const SizedBox.shrink();
  }

  Map<String, dynamic> get() {
    return {"Unknown": "Undefined"};
  }

  bool notify(dynamic d) {
    // do nothing
    return false;
  }

  List<dynamic> getObservers() {
    return [];
  }

  void set(Map<String, dynamic> jo) {
    // sets the component with Json Object
  }
}
