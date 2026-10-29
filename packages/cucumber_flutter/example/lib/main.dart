// A small to-do app. Its behaviour is described in features/todo.feature,
// which test/cucumber_test.dart runs as widget tests.
import 'package:flutter/material.dart';

void main() => runApp(const TodoApp());

/// The app.
class TodoApp extends StatelessWidget {
  /// Creates the app.
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'To-do',
    theme: ThemeData(colorSchemeSeed: Colors.green),
    home: const TodoPage(),
  );
}

/// One item of the list.
class Todo {
  /// Creates an item that is not done yet.
  Todo(this.title);

  /// What to do.
  final String title;

  /// Whether it is done.
  bool done = false;
}

/// The list, with a field to add items.
class TodoPage extends StatefulWidget {
  /// Creates the page.
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _todos = <Todo>[];
  final _field = TextEditingController();

  int get _left => _todos.where((todo) => !todo.done).length;

  void _add() {
    final title = _field.text.trim();
    if (title.isEmpty) return;
    setState(() => _todos.add(Todo(title)));
    _field.clear();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('To-do')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('new-todo'),
                  controller: _field,
                  decoration: const InputDecoration(hintText: 'What to do?'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              IconButton(
                tooltip: 'Add',
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final todo in _todos)
                CheckboxListTile(
                  title: Text(todo.title),
                  value: todo.done,
                  onChanged: (done) => setState(() => todo.done = done!),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _left == 1 ? '1 item left' : '$_left items left',
            key: const Key('left'),
          ),
        ),
      ],
    ),
  );
}
