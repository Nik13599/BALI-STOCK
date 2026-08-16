import 'dart:convert';
import 'dart:io';

void main() {
  final source = File('assets/branding/bali_stock_logo.png.b64');
  if (!source.existsSync()) {
    stderr.writeln('Missing ${source.path}');
    exitCode = 1;
    return;
  }
  final target = File('assets/branding/bali_stock_logo.png');
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(base64Decode(source.readAsStringSync().trim()));
  stdout.writeln('Created ${target.path}');
}
