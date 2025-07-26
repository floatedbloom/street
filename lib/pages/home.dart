import 'package:flutter/material.dart';
import 'others.dart';
import 'you.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  int _selectedIndex = 0;
  late PageController _pageController;

  static const List<Widget> _pages = [
    You(),
    Others(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
          controller: _pageController,
          onPageChanged: _onItemTapped,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'You',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'Others',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}