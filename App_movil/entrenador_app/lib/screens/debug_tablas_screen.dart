import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class DebugTablasScreen extends StatefulWidget {
  const DebugTablasScreen({super.key});

  @override
  State<DebugTablasScreen> createState() => _DebugTablasScreenState();
}

class _DebugTablasScreenState extends State<DebugTablasScreen> {
  List<String> _tablas = [];

  @override
  void initState() {
    super.initState();
    _cargarTablas();
  }

  Future<void> _cargarTablas() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    setState(() {
      _tablas = resultado.map((fila) => fila['name'] as String).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tablas creadas')),
      body: ListView.builder(
        itemCount: _tablas.length,
        itemBuilder: (context, index) => ListTile(
          leading: const Icon(Icons.table_chart),
          title: Text(_tablas[index]),
        ),
      ),
    );
  }
}