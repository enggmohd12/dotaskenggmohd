import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

///
import '../data/hive_data_store.dart';
import '../models/task.dart';
import '../view/home/home_view.dart';

Future<void> checkAndRequestNotificationPermissions(
    BuildContext context) async {
  // Check the current notification permission status
  final status = await Permission.notification.status;

  if (status.isDenied) {
    // Permission has not been granted yet, so request it
    final result = await Permission.notification.request();

    if (result.isPermanentlyDenied) {
      // The user denied the permission permanently, show a dialog to open app settings
      showPermissionDeniedDialog(context);
    }
  } else if (status.isPermanentlyDenied) {
    // The user previously denied the permission permanently, show a dialog to open app settings
    showPermissionDeniedDialog(context);
  }
}

Future<void> showPermissionDeniedDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Notification Permission Required'),
      content: const Text(
        'This app needs notification permissions to remind you about tasks. Please enable notifications in the app settings.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context); // Close the dialog
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context); // Close the dialog
            await openAppSettings(); // Open app settings
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

Future<void> checkAndRequestExactAlarmPermission(BuildContext context) async {
  if (Theme.of(context).platform == TargetPlatform.android) {
    // Check if the platform is Android
    final status = await Permission.scheduleExactAlarm.status;

    if (status.isDenied) {
      // Request the permission
      await Permission.scheduleExactAlarm.request();
    }

    if (status.isPermanentlyDenied) {
      // The user denied the permission permanently, show a dialog to open app settings
      showPermissionDeniedDialog(context);
    }
  }
}

Future<void> scheduleNotification(Task task) async {
  // Initialize timezone database
  tz.initializeTimeZones();

  // Convert the task's createdAt time to a TZDateTime
  final scheduledTime = tz.TZDateTime.from(task.createdAtTime, tz.local);

  // Check if the scheduled time is in the future
  if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
    print(
        "Skipping notification for task '${task.title}' because the scheduled time is in the past.");
    return; // Exit the function if the time is in the past
  }

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'task_channel', // Channel ID
    'Task Notifications', // Channel Name
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final epoch = DateTime.now().millisecondsSinceEpoch;
  final value = epoch % (1 << 31);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    value, // Unique ID for the notification
    task.title, // Notification title
    task.subtitle, // Notification body
    scheduledTime, // The exact time to trigger the notification
    platformChannelSpecifics,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

Future<void> rescheduleNotifications() async {
  /// Open box
  var box = await Hive.openBox<Task>("tasksBox");

  for (var task in box.values) {
    if (!task.isCompleted) {
      await scheduleNotification(task);
    }
  }
}

Future<void> main() async {
  /// Initial Hive DB
  await Hive.initFlutter();

  /// Register Hive Adapter
  Hive.registerAdapter<Task>(TaskAdapter());

  /// Open box
  var box = await Hive.openBox<Task>("tasksBox");

  /// Delete data from previous day
  // ignore: avoid_function_literals_in_foreach_calls
  box.values.forEach((task) {
    if (task.createdAtTime.day != DateTime.now().day) {
      task.delete();
    } else {}
  });

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize Flutter Local Notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Reschedule notifications after reboot
  await rescheduleNotifications();

  runApp(BaseWidget(child: const MyApp()));
}

class BaseWidget extends InheritedWidget {
  BaseWidget({Key? key, required this.child}) : super(key: key, child: child);
  final HiveDataStore dataStore = HiveDataStore();
  final Widget child;

  static BaseWidget of(BuildContext context) {
    final base = context.dependOnInheritedWidgetOfExactType<BaseWidget>();
    if (base != null) {
      return base;
    } else {
      throw StateError('Could not find ancestor widget of type BaseWidget');
    }
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return false;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Check and request notification permissions when the app starts
    checkAndRequestNotificationPermissions(context);
    checkAndRequestExactAlarmPermission(context);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Hive Todo App',
      theme: ThemeData(
        textTheme: const TextTheme(
          headline1: TextStyle(
            color: Colors.black,
            fontSize: 45,
            fontWeight: FontWeight.bold,
          ),
          subtitle1: TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
          headline2: TextStyle(
            color: Colors.white,
            fontSize: 21,
          ),
          headline3: TextStyle(
            color: Color.fromARGB(255, 234, 234, 234),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          headline4: TextStyle(
            color: Colors.grey,
            fontSize: 17,
          ),
          headline5: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          subtitle2: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
          ),
          headline6: TextStyle(
            fontSize: 40,
            color: Colors.black,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      home: const HomeView(),
    );
  }
}
