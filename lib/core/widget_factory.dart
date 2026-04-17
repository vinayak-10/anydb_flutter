import 'gen_interface.dart';
import '../components/text_ascii.dart';
import '../components/text_number.dart';
import '../components/date_time.dart';
import '../components/phone_number.dart';
import '../components/multi_select.dart';
import '../components/drop_down.dart';
import '../components/composite.dart';

class WidgetFactory {
  static GenInterface? get(String type) {
    switch (type) {
      case 'text':
        return TextAscii();
      case 'number':
        return TextNumber();
      case 'dateTime':
        return DateTimeComponent();
      case 'phoneNumber':
        return PhoneNumber();
      case 'multi-select':
        return MultiSelect();
      case 'dropdown':
        return DropDown();
      case 'composite':
        return Composite();
      default:
        return null;
    }
  }
}
