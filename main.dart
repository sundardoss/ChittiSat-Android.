import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:usb_serial/usb_serial.dart';

void main() => runApp(const ChittiSatApp());

class ChittiSatApp extends StatelessWidget {
  const ChittiSatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'satellite',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0C15),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFE7E6EF)),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final SerialService serial = SerialService();
  Timer? _weatherTimer;

  double temperature = 0;
  double humidity = 66;
  double pressure = 0;
  double altitude = 0;
  double x = 0, y = 0, z = 0, ax = 0, ay = 0, az = 0;
  double smoke = -1, methane = -1, lpg = -1, hydrogen = -1;
  String weatherText = 'Partly Cloudy';
  String? selectedPort;
  List<UsbDevice> devices = [];
  String status = 'Disconnected';
  String dataStatus = 'No Data';

  @override
  void initState() {
    super.initState();
    _refreshPorts();
    _loadWeather();
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) => _loadWeather());
    serial.onData = _onSerialData;
    serial.onStatus = (s) => setState(() => status = s);
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    serial.dispose();
    super.dispose();
  }

  Future<void> _refreshPorts() async {
    final list = await UsbSerial.listDevices();
    if (!mounted) return;
    setState(() => devices = list);
  }

  Future<void> _connect() async {
    if (selectedPort == null) return;
    final device = devices.firstWhere((d) => d.deviceName == selectedPort);
    await serial.connect(device, baudRate: 9600);
  }

  void _onSerialData(Uint8List bytes) {
    // The original Windows build parses the device's custom serial stream.
    // This Android port accepts JSON lines when available. Example:
    // {"temperature":24.5,"humidity":62,"pressure":1009,"altitude":125,
    //  "x":1,"y":2,"z":3,"ax":0.1,"ay":0.2,"az":0.3,
    //  "smoke":0.4,"methane":0.1,"lpg":0.2,"hydrogen":0.3}
    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final m = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
        setState(() {
          temperature = _num(m['temperature'], temperature);
          humidity = _num(m['humidity'], humidity);
          pressure = _num(m['pressure'], pressure);
          altitude = _num(m['altitude'], altitude);
          x = _num(m['x'], x); y = _num(m['y'], y); z = _num(m['z'], z);
          ax = _num(m['ax'], ax); ay = _num(m['ay'], ay); az = _num(m['az'], az);
          smoke = _num(m['smoke'], smoke);
          methane = _num(m['methane'], methane);
          lpg = _num(m['lpg'], lpg);
          hydrogen = _num(m['hydrogen'], hydrogen);
          dataStatus = 'Data';
        });
      }
    } catch (_) {}
  }

  double _num(dynamic v, double fallback) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;

  Future<void> _loadWeather() async {
    try {
      // Same service family discovered in the original Flutter binary.
      final pos = await http.get(Uri.parse('http://ip-api.com/json'));
      double lat = 0, lon = 0;
      if (pos.statusCode == 200) {
        final p = jsonDecode(pos.body);
        lat = _num(p['lat'], 0);
        lon = _num(p['lon'], 0);
      }
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon&current_weather=true'
        '&hourly=relativehumidity_2m',
      );
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final cw = d['current_weather'];
        if (cw != null && mounted) {
          setState(() {
            temperature = temperature == 0
                ? _num(cw['temperature'], temperature)
                : temperature;
            final code = _num(cw['weathercode'], 2).round();
            weatherText = _weatherName(code);
          });
        }
      }
    } catch (_) {
      // Keep the dashboard usable when offline.
    }
  }

  String _weatherName(int code) {
    if (code == 0) return 'Sunny';
    if (code <= 3) return 'Partly Cloudy';
    if (code < 70) return 'Rainy';
    return 'Cloudy';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _weatherPanel()),
                      const SizedBox(width: 22),
                      Expanded(flex: 5, child: _movementPanel()),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _airPanel()),
                      const SizedBox(width: 22),
                      Expanded(flex: 5, child: _movementSummaryPanel()),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _bottomBar(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF20202D),
        borderRadius: BorderRadius.circular(30),
      ),
      child: child,
    );
  }

  Widget _weatherPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weather', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _metric('Temperature', '${temperature.toStringAsFixed(0)} °C',
                        'assets/icons/temperature.png'),
                    _metric('Humidity', '${humidity.toStringAsFixed(1)} %',
                        'assets/icons/pressure.png'),
                    _metric('Pressure', '${pressure.toStringAsFixed(1)} Pa',
                        'assets/icons/pressure.png'),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Container(
                  height: 235,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3B),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        weatherText == 'Sunny'
                            ? 'assets/icons/weather/sunny.png'
                            : weatherText == 'Rainy'
                                ? 'assets/icons/weather/rainy.png'
                                : 'assets/icons/weather/partly_cloud.png',
                        width: 120,
                        height: 120,
                      ),
                      Text(weatherText,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, String icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Image.asset(icon, width: 28, height: 28),
          const SizedBox(width: 18),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _airPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Air Quality', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _gas('Smoke', smoke),
                    _gas('Methane', methane),
                    _gas('LPG', lpg),
                    _gas('Hydrogen', hydrogen),
                  ],
                ),
              ),
              SizedBox(
                width: 250,
                height: 250,
                child: CustomPaint(
                  painter: GaugePainter(value: 0),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('None'),
                        SizedBox(height: 8),
                        Text('0', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gas(String name, double value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Text(name),
            const Spacer(),
            Text('${value.toStringAsFixed(2)} ppm',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _movementPanel() {
    return _panel(
      child: SizedBox(
        height: 405,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Movement',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    height: 180,
                    alignment: Alignment.center,
                    child: CustomPaint(
                      painter: SatellitePainter(),
                      size: const Size(180, 180),
                    ),
                  ),
                ],
              ),
            ),
            AltitudeGauge(altitude: altitude),
          ],
        ),
      ),
    );
  }

  Widget _movementSummaryPanel() {
    return _panel(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Spacer(),
          _axis('X', x), _axis('Y', y), _axis('Z', z),
          _axis('AX', ax), _axis('AY', ay), _axis('AZ', az),
        ],
      ),
    );
  }

  Widget _axis(String label, double value) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF535265)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: ${value.toStringAsFixed(1)}${label.length == 1 ? '°' : ''}'),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.usb, size: 22),
          const SizedBox(width: 12),
          const Text('Device Status', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          Text(status,
              style: TextStyle(
                color: status == 'Connected' ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.w800,
              )),
          const Spacer(),
          const Text('Choose Port'),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: selectedPort,
            hint: const Text('Select'),
            items: devices
                .map((d) => DropdownMenuItem<String>(
                      value: d.deviceName,
                      child: Text(d.deviceName ?? 'USB device'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => selectedPort = v),
          ),
          IconButton(onPressed: _refreshPorts, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 30),
          const Icon(Icons.storage),
          const SizedBox(width: 10),
          const Text('Data'),
          const SizedBox(width: 12),
          Text(dataStatus, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(width: 12),
          ElevatedButton(onPressed: _connect, child: const Text('Connect')),
        ],
      ),
    );
  }
}

class AltitudeGauge extends StatelessWidget {
  final double altitude;
  const AltitudeGauge({super.key, required this.altitude});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 360,
      child: CustomPaint(
        painter: AltitudePainter(altitude),
        child: const Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: 0),
            child: Text('Altitude', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

class AltitudePainter extends CustomPainter {
  final double value;
  AltitudePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF555563)..strokeWidth = 2;
    final x = 20.0;
    canvas.drawRect(Rect.fromLTWH(0, 40, 22, size.height - 48), p);
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (int a = 0; a <= 2000; a += 100) {
      final y = 40 + (size.height - 48) * (1 - a / 2000);
      canvas.drawLine(24 + x, y, 65, y, p);
      text.text = TextSpan(
        text: '$a',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      );
      text.layout();
      text.paint(canvas, Offset(68, y - 7));
    }
  }

  @override
  bool shouldRepaint(covariant AltitudePainter oldDelegate) => oldDelegate.value != value;
}

class GaugePainter extends CustomPainter {
  final double value;
  GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .34;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4B4B5C);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        math.radians(140), math.radians(260), false, p);
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) => false;
}

class SatellitePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()..color = const Color(0xFFE8E8EA);
    canvas.drawRect(Rect.fromCenter(center: c.translate(0, 5), width: 100, height: 125), p);
    canvas.drawRect(Rect.fromCenter(center: c.translate(0, -63), width: 60, height: 35), p);
    canvas.drawRect(Rect.fromCenter(center: c.translate(-50, 15), width: 30, height: 90), p);
    canvas.drawRect(Rect.fromCenter(center: c.translate(50, 15), width: 30, height: 90), p);
    final line = Paint()..color = const Color(0xFF777777)..strokeWidth = 1;
    for (int i = -1; i <= 1; i++) {
      canvas.drawLine(Offset(c.dx - 35, c.dy + i * 28),
          Offset(c.dx + 35, c.dy + i * 28), line);
    }
  }

  @override
  bool shouldRepaint(covariant SatellitePainter oldDelegate) => false;
}

class SerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _sub;
  void Function(Uint8List bytes)? onData;
  void Function(String status)? onStatus;

  Future<void> connect(UsbDevice device, {int baudRate = 9600}) async {
    await disconnect();
    final port = await device.create();
    if (port == null) {
      onStatus?.call('Disconnected');
      return;
    }
    if (!await port.open()) {
      onStatus?.call('Disconnected');
      return;
    }
    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    _port = port;
    _sub = port.inputStream?.listen((data) => onData?.call(data));
    onStatus?.call('Connected');
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _port?.close();
    _port = null;
    onStatus?.call('Disconnected');
  }

  void dispose() => disconnect();
}
