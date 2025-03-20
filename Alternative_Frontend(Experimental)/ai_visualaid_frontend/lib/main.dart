import 'package:flutter/material.dart';

void main() {
  runApp(CarouselNavigationApp());
}

class CarouselNavigationApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CarouselPage(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}

class CarouselPage extends StatefulWidget {
  @override
  _CarouselPageState createState() => _CarouselPageState();
}

class _CarouselPageState extends State<CarouselPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Define the pages for the carousel with custom titles
  final List<PageModel> _pages = [
    PageModel(
      title: 'Title A', 
      content: 'Page 1 Content', 
      color: Colors.blue[100]!
    ),
    PageModel(
      title: 'Title B', 
      content: 'Page 2 Content', 
      color: Colors.green[100]!
    ),
    PageModel(
      title: 'Title C', 
      content: 'Page 3 Content', 
      color: Colors.orange[100]!
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Page Title Bubble
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _pages[_currentPage].title, // Use custom title here
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            // Expanded PageView for swiping
            Expanded(
              child: PageView(
                controller: _pageController,
                children: _pages.map((page) => PageContent(
                  title: page.title,
                  content: page.content,
                  color: page.color,
                )).toList(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// New model to hold page information
class PageModel {
  final String title;
  final String content;
  final Color color;

  PageModel({
    required this.title, 
    required this.content, 
    required this.color
  });
}

class PageContent extends StatelessWidget {
  final String title;
  final String content;
  final Color color;

  const PageContent({
    Key? key, 
    required this.title,
    required this.content, 
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Center(
        child: Text(
          content,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}