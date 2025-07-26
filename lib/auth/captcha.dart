import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Captcha extends StatefulWidget {
  final Function(String) onCompleted;
  final Function()? onError;
  final double height;
  
  const Captcha({
    super.key,
    required this.onCompleted,
    this.onError,
    this.height = 200,
  });

  @override
  State<Captcha> createState() => _CaptchaState();
}

class _CaptchaState extends State<Captcha> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeCaptcha();
  }

  void _initializeCaptcha() {
    final captchaUrl = dotenv.env['CAPTCHA_URL'] ?? '';
    final siteKey = dotenv.env['HCAPTCHA_SITE_KEY'] ?? '';
    
    if (captchaUrl.isEmpty || siteKey.isEmpty) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      widget.onError?.call();
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Captcha',
        onMessageReceived: (JavaScriptMessage message) {
          print('Embedded captcha completed: ${message.message}');
          widget.onCompleted(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('Embedded captcha error: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
            widget.onError?.call();
          },
        ),
      )
      ..loadRequest(Uri.parse('$captchaUrl?sitekey=$siteKey'));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (!_hasError)
              WebViewWidget(controller: _controller),
            
            if (_isLoading)
              Container(
                color: Colors.grey.withValues(alpha: 0.1),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text(
                        'Loading security check...',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (_hasError)
              Container(
                color: Colors.red.withValues(alpha: 0.1),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Failed to load captcha',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _hasError = false;
                          });
                          _initializeCaptcha();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
} 