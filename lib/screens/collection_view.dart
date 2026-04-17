import 'package:flutter/material.dart';
import '../services/element_db.dart';
import '../models/element_model.dart';
import 'element_editor.dart';

class CollectionView extends StatefulWidget {
  final List<ElementDb> dbs;
  final String title;

  const CollectionView({super.key, required this.dbs, required this.title});

  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  final int _selectedDbIndex = 0;
  String _currentFilter = 'Active';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCurrentDb();
  }

  Future<void> _initCurrentDb() async {
    if (widget.dbs.isNotEmpty) {
      await widget.dbs[_selectedDbIndex].initDb();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dbs.isEmpty) {
      return const Scaffold(body: Center(child: Text("No Databases in this Schema")));
    }

    final currentDb = widget.dbs[_selectedDbIndex];
    final filteredElements = currentDb.applyFilter(_currentFilter)
        .where((e) => _searchQuery.isEmpty || e.match(_searchQuery)[0])
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.title}: ${currentDb.key}"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110.0),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search ${currentDb.key}...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              // Filter Chips
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['Active', 'Archived', 'Deleted', 'All'].map((f) => 
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _currentFilter == f,
                      onSelected: (selected) => setState(() => _currentFilter = f),
                    ),
                  )
                ).toList(),
              ),
            ],
          ),
        ),
      ),
      body: ListView.separated(
        itemCount: filteredElements.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final element = filteredElements[index];
          return ListTile(
            title: Text(element.key, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: element.getDisplays(onlyValue: true),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => ElementEditor(
                  db: currentDb, 
                  element: element,
                ))
              );
              setState(() {}); // Refresh list after edit
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newElement = ElementModel();
          newElement.init(currentDb.dbSchema, currentDb.intf);
          // Key generation or user input for key needed
          newElement.key = "Record ${currentDb.elements.length + 1}";
          
          await Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => ElementEditor(
              db: currentDb, 
              element: newElement,
              isNew: true,
            ))
          );
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
