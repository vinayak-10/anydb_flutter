import 'gen_interface.dart';
import '../components/text_ascii.dart';
import '../components/text_number.dart';
import '../components/date_time.dart';
import '../components/phone_number.dart';
import '../components/multi_select.dart';
import '../components/drop_down.dart';
import '../components/composite.dart';
import '../components/list_header.dart';
import '../components/simple_account.dart';
import '../components/multi_value.dart';
import '../components/formatted_text.dart';
import '../components/reminder.dart';
import '../components/meta_display.dart';

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
      case 'list-header':
        return ListHeader();
      case 'simple-account':
        return SimpleAccount();
      case 'multi-value':
        return MultiValue();
      case 'formatted-text':
        return FormattedText();
      case 'reminder':
        return Reminder();
      case 'meta':
      case 'meta-display':
        return MetaDisplay();
      default:
        return null;
    }
  }
}
