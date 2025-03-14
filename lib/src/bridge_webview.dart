import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:whiteboard_sdk_flutter/whiteboard_sdk_flutter.dart';

class DsBridgeWebView extends StatefulWidget {
  final BridgeCreatedCallback onDSBridgeCreated;

  DsBridgeWebView({
    Key? key,
    required this.onDSBridgeCreated,
  }) : super(key: key);

  @override
  DsBridgeWebViewState createState() => DsBridgeWebViewState();
}

class DsBridgeWebViewState extends State<DsBridgeWebView> {
  DsBridgeBasic dsBridge = DsBridgeBasic();
  late WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final PlatformWebViewControllerCreationParams params =
        PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished, // ✅ Fixed duplicate method
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..addJavaScriptChannel(
        'DsBridge',
        onMessageReceived: dsBridge.handleJavascriptMessage,
      )
      ..addJavaScriptChannel(
        'consoleLog', // ✅ Added console logging
        onMessageReceived: _onConsoleMessage,
      )
      ..loadFlutterAsset("packages/whiteboard_sdk_flutter/assets/whiteboardBridge/index.html");

    await _controller.setUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 DsBridge/1.0.0");

    dsBridge.initController(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  void _onPageStarted(String url) {
    debugPrint('WebView Page started loading: $url');
  }

  Future<void> _onPageFinished(String url) async {
    debugPrint('WebView Page finished loading: $url');
    if (url.endsWith("whiteboardBridge/index.html")) {
      await Future<void>.delayed(Duration(seconds: 1)); // ✅ Ensure JS is fully loaded
      await dsBridge.runCompatScript();
      widget.onDSBridgeCreated(dsBridge);
    }
  }

  void _onWebResourceError(WebResourceError error) {
    debugPrint('WebView resource error: ${error.description}');
  }

  void _onConsoleMessage(JavaScriptMessage message) {
    debugPrint("[WebView Console] ${message.message}");
  }
}

class DsBridgeBasic extends DsBridge {
  static const _compatDsScript = """
    if (!window.__dsbridge) {
        window.__dsbridge = {
            postMessage: function(msg) {
                console.log("dsbridge message:", msg);
            }
        };
    }
    window._dsbridge = {
        call: function (method, arg) {
            console.log(`call flutter webview \${method} \${arg}`);
            window.__dsbridge.postMessage(JSON.stringify({ "method": method, "args": arg }));
            return '{}';
        }
    };
    console.log("Injected dsbridge manually.");
  """;

  late WebViewController _controller;

  void initController(WebViewController controller) {
    _controller = controller;
  }

  Future<void> runCompatScript() async {
    try {
      await _controller.runJavaScript(_compatDsScript);
    } catch (e) {
      print("WebView bridge run compat script error: $e");
    }
  }

  void handleJavascriptMessage(JavaScriptMessage message) {
    var res = jsonDecode(message.message);
    javascriptInterface.call(res["method"], res["args"]);
  }

  @override
  FutureOr<String?> evaluateJavascript(String javascript) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(javascript);
      return result is String ? result : result.toString();
    } catch (e) {
      print("WebView bridge evaluateJavascript error: $e");
      return null;
    }
  }
}
