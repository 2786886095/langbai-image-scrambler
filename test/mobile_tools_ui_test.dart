import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langbai_image_scrambler/src/fun_tools/fun_tools_screen.dart';
import 'package:langbai_image_scrambler/src/video/video_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reviewGoldens = bool.fromEnvironment('REVIEW_MOBILE_UI');

void main() {
  setUpAll(() async {
    final font = FontLoader('NotoSansCJKSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([font.load(), icons.load()]);
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5271FF),
            brightness: Brightness.dark,
          ),
          fontFamily: 'NotoSansCJKSC',
          useMaterial3: true,
        ),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('手机端视频模式切换保持各自算法', (tester) async {
    SharedPreferences.setMockInitialValues({
      'video_mode_restore': false,
      'video_scramble_algorithm': 'block_shuffle',
      'video_restore_algorithm': 'auto',
      'video_scramble_performance': 'full',
      'video_restore_performance': 'normal',
    });
    await pumpScreen(tester, const VideoScreen(), const Size(390, 844));

    expect(find.text('网格分块打乱'), findsOneWidget);
    expect(find.text('全功率'), findsOneWidget);
    await tester.tap(find.text('一键还原'));
    await tester.pumpAndSettle();
    expect(find.text('自动识别'), findsOneWidget);
    expect(find.text('普通'), findsOneWidget);
    await tester.tap(find.text('视频混淆'));
    await tester.pumpAndSettle();
    expect(find.text('网格分块打乱'), findsOneWidget);
    expect(find.text('全功率'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (_reviewGoldens) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/video_tools_android_390x844.png'),
      );
    }
  });

  testWidgets('小屏手机视频界面可滚动且无布局溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester, const VideoScreen(), const Size(360, 640));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.text('生成混淆视频并导出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机端趣味工具恢复持久化版本且无布局溢出', (tester) async {
    SharedPreferences.setMockInitialValues({
      'fun_tool_type': 'cloak',
      'fun_cloak_version': 'v2',
      'fun_cloak_difference': 36.0,
    });
    await pumpScreen(tester, const FunToolsScreen(), const Size(390, 844));
    expect(find.text('v2 · 高容量隐藏'), findsOneWidget);
    expect(find.text('数据色差 36'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (_reviewGoldens) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fun_tools_android_390x844.png'),
      );
    }
  });

  testWidgets('手机横屏趣味工具可滚动且控件可触达', (tester) async {
    SharedPreferences.setMockInitialValues({'fun_tool_type': 'prism'});
    await pumpScreen(tester, const FunToolsScreen(), const Size(844, 390));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
    expect(find.text('立即生成 PNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机端新增页面支持繁体中文', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(
      tester,
      const VideoScreen(traditional: true),
      const Size(390, 844),
    );
    expect(find.text('生成可播放的混淆影片'), findsOneWidget);
    expect(find.text('選擇影片'), findsOneWidget);
    expect(find.text('Gilbert 曲線逐幀混淆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 视频双栏界面无布局溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester, const VideoScreen(), const Size(1440, 900));
    expect(find.text('导入视频'), findsOneWidget);
    expect(find.text('处理设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (_reviewGoldens) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/video_tools_windows_1440x900.png'),
      );
    }
  });

  testWidgets('Windows 趣味工具双栏输入界面无布局溢出', (tester) async {
    SharedPreferences.setMockInitialValues({'fun_tool_type': 'prism'});
    await pumpScreen(tester, const FunToolsScreen(), const Size(1440, 900));
    expect(find.text('选择里图'), findsOneWidget);
    expect(find.text('选择表图'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (_reviewGoldens) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/fun_tools_windows_1440x900.png'),
      );
    }
  });
}
