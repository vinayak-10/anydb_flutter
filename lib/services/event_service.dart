import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppEvent {
  final String name;
  final dynamic data;
  AppEvent(this.name, this.data);
}

class EventService {
  final _controller = StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  void emit(String name, [dynamic data]) {
    _controller.add(AppEvent(name, data));
  }

  void dispose() {
    _controller.close();
  }
}

final eventServiceProvider = Provider((ref) => EventService());
