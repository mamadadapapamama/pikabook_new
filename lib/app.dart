import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
