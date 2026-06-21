import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/gen_interface.dart';
import '../core/widget_factory.dart';
import '../utils/feedback_toast.dart';

class SimpleAccount extends GenInterface {
  String name = '';
  String id = '';
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;
  List<dynamic> values = [];
  List<GenInterface> componentsArray = [];
  Map<String, dynamic> config = {};
  Map<String, String> idMap = {};
  String version = "1.0.0";

  @override
  String getType() => "simple-account";

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

    config = {
      "overrideTransaction": {"keys": []},
      "notify": [],
      "onEdit": {"confirm": false},
    };
    if (jsonObj.containsKey('config')) {
      final jc = jsonObj['config'] as Map<String, dynamic>;
      if (jc.containsKey('overrideTransaction')) {
        config['overrideTransaction'] = jc['overrideTransaction'];
      }
      if (jc.containsKey('notify')) {
        config['notify'] = jc['notify'];
      }
      if (jc.containsKey('onEdit')) {
        config['onEdit'] = jc['onEdit'];
      }
    }

    _schema = jsonObj['schema'] != null ? [jsonObj['schema']] : [];
    if (jsonObj['schema'] != null && jsonObj['schema']['version'] != null) {
      version = jsonObj['schema']['version'];
    }

    idMap = {};
    _prepareIdMap();
  }

  List<dynamic> _schema = [];

  void _prepareIdMap() {
    if (_schema.isEmpty) return;
    final c = WidgetFactory.get("composite");
    if (c != null) {
      c.init(_schema[0], repoIntf);
      for (int i = 0; ; i++) {
        final ic = c.getComponentAtIndex(i);
        if (ic == null) break;
        idMap[ic.getId()] = ic.getName();
      }
    }
  }

  String id2name(String id) => idMap[id] ?? "";

  @override
  GenInterface clone() {
    final c = SimpleAccount();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      final data = jsonDb[name] as Map<String, dynamic>;
      if (data.isNotEmpty) {
        values = data.values.first as List<dynamic>;
        _prepareComponents();
      }
    }
  }

  void _prepareComponents() {
    componentsArray = [];
    for (var val in values) {
      final c = WidgetFactory.get("composite");
      if (c != null) {
        c.init(_schema[0], repoIntf);
        c.populate({c.getName(): val});
        componentsArray.add(c);
      }
    }
  }

  @override
  Map<String, dynamic> fetch() {
    List<dynamic> fetchedValues = [];
    for (var c in componentsArray) {
      fetchedValues.add(c.fetch().values.first);
    }
    values = fetchedValues;
    return {
      name: {version: fetchedValues},
    };
  }

  double calculateDues() {
    final debit = _sumById('Debit');
    final credit = _sumById('Credit');
    final discount = _sumById('Discount');
    return debit - (credit + discount);
  }

  double _sumById(String id) {
    final fieldName = id2name(id);
    if (fieldName.isEmpty) return 0;

    double s = 0;
    for (var c in componentsArray) {
      final cData = c.fetch().values.first as Map<String, dynamic>;
      if (cData.containsKey(fieldName)) {
        s += _parseDouble(cData[fieldName]);
      }
    }
    return s;
  }

  double getLastBalance() {
    final balanceField = id2name("Balance");
    if (componentsArray.isNotEmpty && balanceField.isNotEmpty) {
      final lastVal =
          componentsArray[0].fetch().values.first as Map<String, dynamic>;
      if (lastVal.containsKey(balanceField)) {
        return _parseDouble(lastVal[balanceField]);
      }
    }
    return calculateDues();
  }

  int getLastTransactionTime() {
    final dateField = id2name("Transaction-Date");
    if (componentsArray.isNotEmpty && dateField.isNotEmpty) {
      final lastVal =
          componentsArray[0].fetch().values.first as Map<String, dynamic>;
      if (lastVal.containsKey(dateField)) {
        final d = lastVal[dateField];
        return d is int ? d : (int.tryParse(d.toString()) ?? 0);
      }
    }
    return 0;
  }

  String getLastTransactionDate() {
    final ts = getLastTransactionTime();
    if (ts == 0) return "";
    final dateStr = DateFormat(
      'E, MMM d y',
    ).format(DateTime.fromMillisecondsSinceEpoch(ts));

    String details = dateStr;
    final creditName = id2name("Credit");
    final modeName = id2name("Payment-Mode");

    if (componentsArray.isNotEmpty) {
      final lastVal =
          componentsArray[0].fetch().values.first as Map<String, dynamic>;
      if (creditName.isNotEmpty && lastVal.containsKey(creditName)) {
        details += ", $creditName: ${lastVal[creditName]}";
      }
      if (modeName.isNotEmpty && lastVal.containsKey(modeName)) {
        details += ", $modeName: ${lastVal[modeName]}";
      }
    }
    return details;
  }

  void updateObservers(
    GenInterface notifier,
    Map<String, dynamic> data,
    List<dynamic> observerIndexes,
    GenInterface cs,
  ) {
    final String value = data.values.first.toString();
    final String notifierId = notifier.getId();

    if (notifierId == "Debit") {
      double charges = double.tryParse(value) ?? 0;
      if (charges < 0) charges = 0;

      // Auto-update Paid to equal Charges (Credit = Debit) for seamless full payment interactive behavior
      final pc = _findIn(cs, 'Credit');
      if (pc != null) {
        pc.populate({pc.getName(): charges.toStringAsFixed(0)});
      }

      // Auto-update Discount to 0
      final pd = _findIn(cs, 'Discount');
      if (pd != null) {
        pd.populate({pd.getName(): "0"});
      }

      final pb = _findIn(cs, 'Balance');
      if (pb != null) {
        double balance =
            getLastBalance(); // Charges and Paid are equal, so (charges - paid) is 0
        pb.populate({pb.getName(): balance.toStringAsFixed(0)});
      }
    } else if (notifierId == "Credit") {
      double paid = double.tryParse(value) ?? 0;
      if (paid < 0) paid = 0;
      final cc = _findIn(cs, 'Debit');
      double charges = double.tryParse(cc?.getValue() ?? "0") ?? 0;

      double discount = 0;
      if (paid >= charges) {
        discount = 0;
      } else {
        // Auto-calculate discount as the difference (Charges - Paid) clamped to >= 0
        discount = charges - paid;
      }

      final pd = _findIn(cs, 'Discount');
      if (pd != null) {
        pd.populate({pd.getName(): discount.toStringAsFixed(0)});
      }

      final pb = _findIn(cs, 'Balance');
      if (pb != null) {
        double balance = getLastBalance() + (charges - (paid + discount));
        pb.populate({pb.getName(): balance.toStringAsFixed(0)});
      }
    } else if (notifierId == "Discount") {
      double discount = double.tryParse(value) ?? 0;
      if (discount < 0) discount = 0;
      final cc = _findIn(cs, 'Debit');
      double charges = double.tryParse(cc?.getValue() ?? "0") ?? 0;
      final pc = _findIn(cs, 'Credit');
      double paid = double.tryParse(pc?.getValue() ?? "0") ?? 0;

      if (paid >= charges) {
        discount = 0;
        final pd = _findIn(cs, 'Discount');
        if (pd != null) {
          pd.populate({pd.getName(): "0"});
        }
      } else if (discount > charges) {
        discount = charges;
        paid = 0;
        final pd = _findIn(cs, 'Discount');
        if (pd != null) {
          pd.populate({pd.getName(): charges.toStringAsFixed(0)});
        }
        if (pc != null) {
          pc.populate({pc.getName(): "0"});
        }
      } else if (paid + discount > charges) {
        // If the sum exceeds charges, we auto-reduce paid so they sum to charges (no overpayment/excess discount)
        paid = charges - discount;
        if (paid < 0) paid = 0;
        if (pc != null) {
          pc.populate({pc.getName(): paid.toStringAsFixed(0)});
        }
      } else {
        // If paid + discount <= charges, we do NOT change paid!
        // This decouples the inputs and allows outstanding dues to be recorded properly!
      }

      final pb = _findIn(cs, 'Balance');
      if (pb != null) {
        double balance = getLastBalance() + (charges - (paid + discount));
        pb.populate({pb.getName(): balance.toStringAsFixed(0)});
      }
    } else if (notifierId == "Balance") {
      double currentBalance = double.tryParse(value) ?? 0;
      final cd = _findIn(cs, 'Debit');
      double debit = double.tryParse(cd?.getValue() ?? "0") ?? 0;
      double lastBalance = getLastBalance();
      double newCredit = currentBalance - lastBalance + debit;
      if (newCredit < 0) newCredit = 0;

      // Populate Credit directly in cs
      final pc = _findIn(cs, 'Credit');
      if (pc != null) {
        pc.populate({pc.getName(): newCredit.toStringAsFixed(0)});
      }
    }
  }

  void _populateBalance(GenInterface cs) {
    final pb = _findIn(cs, 'Balance');
    if (pb == null) return;

    double lastBalance = getLastBalance();
    double debit =
        double.tryParse(_findIn(cs, 'Debit')?.getValue() ?? "0") ?? 0;
    double credit =
        double.tryParse(_findIn(cs, 'Credit')?.getValue() ?? "0") ?? 0;
    double discount =
        double.tryParse(_findIn(cs, 'Discount')?.getValue() ?? "0") ?? 0;

    double balance = lastBalance + (debit - (credit + discount));
    pb.populate({pb.getName(): balance.toStringAsFixed(0)});
  }

  GenInterface? _findIn(GenInterface cs, String id) {
    int idx = cs.getComponentIdIndex(id);
    return idx != -1 ? cs.getComponentAtIndex(idx) : null;
  }

  Map<String, dynamic> _validateOne(GenInterface component) {
    debugPrint("!!! VALIDATION TRIGGERED !!!");
    // 1. First run generic validation for all fields
    final res = component.validate();
    if (res['valid'] == false) {
      debugPrint("VALIDATION FAILED (Generic): ${res['constraint']}");
      return res;
    }

    // 2. Explicitly double-check Payment-Mode by ID for extra safety
    int modeIdx = component.getComponentIdIndex("Payment-Mode");
    GenInterface? modeComp;

    if (modeIdx != -1) {
      modeComp = component.getComponentAtIndex(modeIdx);
    } else {
      // Very broad check: search all components for one named "Mode"
      for (int i = 0; ; i++) {
        final c = component.getComponentAtIndex(i);
        if (c == null) break;
        if (c.getName().toLowerCase() == "mode") {
          modeComp = c;
          break;
        }
      }
    }

    if (modeComp != null) {
      final mRes = modeComp.validate();
      if (mRes['valid'] == false) {
        debugPrint("VALIDATION FAILED (Explicit Mode): ${mRes['constraint']}");
        return mRes;
      }

      // Final catch-all for empty lists/strings
      final val = modeComp.fetch().values.first;
      final valStr = val.toString().trim();
      if (val == null ||
          (val is List && val.isEmpty) ||
          valStr.isEmpty ||
          valStr == "[]" ||
          valStr == "null") {
        return {
          'valid': false,
          'name': 'Required Field',
          'constraint': 'Field Required: Transaction Mode must be specified.',
        };
      }
    }

    return {'valid': true, 'name': '', 'constraint': ''};
  }

  @override
  Map<String, dynamic> validate() {
    for (var c in componentsArray) {
      final res = _validateOne(c);
      if (!res['valid']) return res;
    }
    return {'valid': true, 'name': '', 'constraint': ''};
  }

  @override
  Widget editor({
    required Key key,
    required Function(dynamic) onChanged,
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs,
    int? index,
    bool? autoFocus,
    bool? refresh,
  }) {
    return _SimpleAccountEditor(
      key: key,
      account: this,
      onChanged: onChanged,
      cbNotifyParent: cbNotifyParent,
    );
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    if (onlyValue) return _SimpleAccountSummary(account: this);
    return _SimpleAccountDisplay(account: this, onChanged: onChanged);
  }

  @override
  Widget? invoke({
    required String method,
    required Map<String, dynamic> parameters,
    VoidCallback? onChanged,
  }) {
    if (method == 'get-dues') return _SimpleAccountSummary(account: this);
    if (method == 'add-one') {
      return Builder(
        builder: (context) {
          return Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text(
                "Add New Transaction",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              onPressed: () async {
                final newComp = getOne();
                if (newComp != null) {
                  String? errorMessage;
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setModalState) => AlertDialog(
                        title: const Text(
                          "Add New Transaction",
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: SingleChildScrollView(
                          child: SizedBox(
                            width: double.maxFinite,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red,
                                        width: 4,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      errorMessage!,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                newComp.editor(
                                  key: const ValueKey("modal_add_tx"),
                                  onChanged: (val) {},
                                  cbNotifyParent: (notifier, data, observers) {
                                    setModalState(() {
                                      updateObservers(
                                        notifier,
                                        data,
                                        observers,
                                        newComp,
                                      );
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text(
                              "CANCEL",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final v = _validateOne(newComp);
                              if (v['valid'] == true) {
                                Navigator.pop(context, true);
                              } else {
                                setModalState(() {
                                  errorMessage = v['constraint'];
                                });
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Color(0xFFE9967A),
                                          size: 28,
                                        ),
                                        SizedBox(width: 8),
                                        Text("Missing Information"),
                                      ],
                                    ),
                                    content: Text(
                                      "${v['constraint']}\n\nPlease complete the required fields.",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text(
                                          "OK",
                                          style: TextStyle(
                                            color: Color(0xFF6B1524),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              "ADD",
                              style: TextStyle(
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (result == true) {
                    componentsArray.insert(0, newComp);
                    if (onChanged != null) onChanged();
                    FeedbackToast.success(
                      context,
                      "Transaction added successfully",
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                elevation: 1,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          );
        },
      );
    }
    return null;
  }

  GenInterface? getOne() {
    final component = WidgetFactory.get("composite");
    if (component == null) return null;
    component.init(_schema[0], repoIntf);

    final overrideKeys =
        config['overrideTransaction']?['keys'] as List<dynamic>?;
    if (componentsArray.isNotEmpty && overrideKeys != null) {
      final lastTxValue =
          componentsArray[0].fetch().values.first as Map<String, dynamic>;
      final Map<String, dynamic> initialValue = {};
      for (var k in overrideKeys) {
        if (lastTxValue.containsKey(k))
          initialValue[k.toString()] = lastTxValue[k];
      }
      component.populate({component.getName(): initialValue});
    }
    _populateBalance(component);
    return component;
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}

class _SimpleAccountDisplay extends StatefulWidget {
  final SimpleAccount account;
  final VoidCallback? onChanged;
  const _SimpleAccountDisplay({required this.account, this.onChanged});

  @override
  State<_SimpleAccountDisplay> createState() => _SimpleAccountDisplayState();
}

class _SimpleAccountDisplayState extends State<_SimpleAccountDisplay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SimpleAccountSummary(account: widget.account)),
            IconButton(
              icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
            ),
          ],
        ),
        if (_isExpanded) ...[
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.account.componentsArray.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = widget.account.componentsArray[index];
              return Dismissible(
                key: ValueKey("view_tx_${c.hashCode}_$index"),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Delete Transaction"),
                      content: const Text(
                        "Are you sure you want to delete this transaction?",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("CANCEL"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            "DELETE",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) {
                  setState(() {
                    widget.account.componentsArray.remove(c);
                    widget.account.fetch(); // Refresh internal values
                  });
                  if (widget.onChanged != null) widget.onChanged!();
                  FeedbackToast.success(
                    context,
                    "Transaction deleted successfully",
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      c.display(onlyValue: false),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            iconSize: 36,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Delete Transaction?"),
                                  content: const Text(
                                    "Are you sure you want to delete this transaction?",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("CANCEL"),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text(
                                        "DELETE",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                setState(() {
                                  widget.account.componentsArray.remove(c);
                                  widget.account.fetch();
                                });
                                if (widget.onChanged != null)
                                  widget.onChanged!();
                                FeedbackToast.success(
                                  context,
                                  "Transaction deleted successfully",
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _SimpleAccountSummary extends StatelessWidget {
  final SimpleAccount account;
  const _SimpleAccountSummary({required this.account});

  @override
  Widget build(BuildContext context) {
    final dues = account.calculateDues();
    final lastDate = account.getLastTransactionDate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12.0,
          runSpacing: 8.0,
          children: [
            _stat(
              "Entries",
              account.componentsArray.length.toDouble(),
              Colors.blueGrey,
            ),
            _stat("Charges", account._sumById('Debit'), Colors.green),
            _stat("Paid", account._sumById('Credit'), Colors.green),
            _stat("Disc", account._sumById('Discount'), Colors.orange),
            _stat(
              "Balance",
              dues,
              dues == 0 ? Colors.green : (dues > 0 ? Colors.red : Colors.blue),
            ),
          ],
        ),
        if (lastDate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2.0),
                  child: Icon(Icons.history, size: 15, color: Colors.blue),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Last Transaction: $lastDate",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blue,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stat(String label, double val, Color color) {
    if (val == 0 && label != "Balance" && label != "Entries")
      return const SizedBox.shrink();
    final prefix = label == "Entries" ? "" : "₹";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        "$label: $prefix${val.abs().toStringAsFixed(0)}",
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SimpleAccountEditor extends StatefulWidget {
  final SimpleAccount account;
  final Function(dynamic) onChanged;
  final Function(GenInterface, Map<String, dynamic>, List<dynamic>)?
  cbNotifyParent;

  const _SimpleAccountEditor({
    super.key,
    required this.account,
    required this.onChanged,
    this.cbNotifyParent,
  });

  @override
  State<_SimpleAccountEditor> createState() => _SimpleAccountEditorState();
}

class _SimpleAccountEditorState extends State<_SimpleAccountEditor> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final txList = widget.account.componentsArray;
    final displayList = _showAll ? txList : txList.take(3).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAddButton(context),
          const SizedBox(height: 20),
          const Text(
            "TRANSACTIONS",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.blueGrey,
            ),
          ),
          const Divider(),
          Column(
            children: displayList.asMap().entries.map((entry) {
              final index = entry.key;
              final c = entry.value;
              return Column(
                children: [
                  Dismissible(
                    key: ValueKey("editor_tx_${c.hashCode}_$index"),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Delete Transaction"),
                          content: const Text(
                            "Are you sure you want to delete this transaction?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("CANCEL"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                "DELETE",
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (direction) {
                      setState(() {
                        widget.account.componentsArray.remove(c);
                        widget.account.fetch();
                      });
                      widget.onChanged(widget.account.fetch());
                      FeedbackToast.success(
                        context,
                        "Transaction deleted successfully",
                      );
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            c.editor(
                              key: ValueKey("tx_edit_${c.hashCode}"),
                              onChanged: (val) {
                                setState(() {
                                  widget.account.fetch();
                                });
                                widget.onChanged(widget.account.fetch());
                              },
                              cbNotifyParent: (notifier, data, observers) {
                                setState(() {
                                  widget.account.updateObservers(
                                    notifier,
                                    data,
                                    observers,
                                    c,
                                  );
                                });
                                widget.onChanged(widget.account.fetch());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  iconSize: 36,
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text(
                                          "Delete Transaction?",
                                        ),
                                        content: const Text(
                                          "Are you sure you want to delete this transaction?",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text("CANCEL"),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text(
                                              "DELETE",
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() {
                                        widget.account.componentsArray.remove(
                                          c,
                                        );
                                        widget.account.fetch();
                                      });
                                      widget.onChanged(widget.account.fetch());
                                      FeedbackToast.success(
                                        context,
                                        "Transaction deleted successfully",
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index < displayList.length - 1) const Divider(),
                ],
              );
            }).toList(),
          ),
          if (txList.length > 3)
            Center(
              child: TextButton.icon(
                icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _showAll
                      ? "Show Less"
                      : "Show More (${txList.length - 3} more)",
                ),
                onPressed: () => setState(() => _showAll = !_showAll),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
        label: const Text(
          "Add New Transaction",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        onPressed: () async {
          final newComp = widget.account.getOne();
          if (newComp != null) {
            String? errorMessage;
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => StatefulBuilder(
                builder: (context, setModalState) => AlertDialog(
                  title: const Text(
                    "Add New Transaction",
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: double.maxFinite,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 4),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          newComp.editor(
                            key: const ValueKey("modal_add_tx"),
                            onChanged: (val) {},
                            cbNotifyParent: (notifier, data, observers) {
                              setModalState(() {
                                widget.account.updateObservers(
                                  notifier,
                                  data,
                                  observers,
                                  newComp,
                                );
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        "CANCEL",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final v = widget.account._validateOne(newComp);
                        if (v['valid'] == true) {
                          Navigator.pop(context, true);
                        } else {
                          setModalState(() {
                            errorMessage = v['constraint'];
                          });
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFE9967A),
                                    size: 28,
                                  ),
                                  SizedBox(width: 8),
                                  Text("Missing Information"),
                                ],
                              ),
                              content: Text(
                                "${v['constraint']}\n\nPlease complete the required fields.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text(
                                    "OK",
                                    style: TextStyle(
                                      color: Color(0xFF6B1524),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      child: const Text(
                        "ADD",
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (result == true) {
              setState(() {
                widget.account.componentsArray.insert(0, newComp);
                widget.account.fetch();
              });
              widget.onChanged(widget.account.fetch());
              FeedbackToast.success(context, "Transaction added successfully");
            }
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
