import 'package:flutter/material.dart';
import 'history.dart';
import 'you.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    You(),
    History(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Streetly"),
          centerTitle: true,
        ),
        body: PageView(
          controller: PageController(initialPage: _selectedIndex),
          onPageChanged: _onItemTapped,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'You',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'History',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}