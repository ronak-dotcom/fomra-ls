import 'package:flutter/material.dart';
import '../../models/employee_profile.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/employee_service.dart';
import '../../services/notifications_service.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_input.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/portal_home_sections.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';

// ── Portal modes ──────────────────────────────────────────────────────────────

enum TaskPortalMode { full, employee, management }

/// Shared in-memory task list (management adds, employees view).
final List<Task> sharedTasks = [];

int taskCountForLead(String leadId) {
  final link = 'land_lead:$leadId';
  return sharedTasks.where((t) => t.module == link).length;
}

String? leadIdFromTaskModule(String module) {
  const prefix = 'land_lead:';
  if (!module.startsWith(prefix)) return null;
  final id = module.substring(prefix.length).trim();
  return id.isEmpty ? null : id;
}

List<Task> tasksForLead(String leadId) {
  final link = 'land_lead:$leadId';
  return sharedTasks.where((t) => t.module == link).toList();
}

/// Push live notifications to the bell when a task is created.
void notifyTaskCreated(Task task) {
  if (AuthService.instance.isManagement) {
    if (task.assignedTo.isEmpty) return;
    final who = task.assignedTo.join(', ');
    NotificationsService.create(
      audience: 'employee',
      type: 'task',
      title: 'New task assigned',
      message: '${task.title} — assigned to $who',
    ).catchError((_) {});
    return;
  }
  final who = AuthService.instance.currentUser?.fullName ?? 'An employee';
  final leadId = leadIdFromTaskModule(task.module);
  NotificationsService.create(
    audience: 'management',
    type: 'task',
    title: 'New task from $who',
    message: task.title,
    leadId: leadId,
  ).catchError((_) {});
}

void notifyTaskStatusChanged(Task task, TaskStatus status) {
  if (AuthService.instance.isManagement) return;
  final who = AuthService.instance.currentUser?.fullName ?? 'An employee';
  NotificationsService.create(
    audience: 'management',
    type: 'task',
    title: 'Task update by $who',
    message: '${task.title} → ${_statusLabel(status)}',
  ).catchError((_) {});
}

void applyTaskStatusChange(Task task, TaskStatus status) {
  final changed = task.status != status;
  task.status = status;
  if (status == TaskStatus.done) task.completedAt = DateTime.now();
  if (changed) notifyTaskStatusChanged(task, status);
}

Future<void> showTaskDetailSheet(BuildContext context, Task task) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TaskDetailSheet(
      task: task,
      onStatusChange: (s) => applyTaskStatusChange(task, s),
    ),
  );
}

Future<void> showLeadTasksSheet(
  BuildContext context, {
  required String leadId,
  String? leadLabel,
}) {
  final tasks = tasksForLead(leadId);
  final title = leadLabel != null && leadLabel.trim().isNotEmpty
      ? 'Tasks — ${leadLabel.trim()}'
      : 'Tasks — Lead #$leadId';

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: ctx.fomraSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${tasks.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.task_alt_outlined,
                            size: 44,
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No tasks for this lead yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ctx.fomraTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.all(12),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final task = tasks[i];
                        return _TaskCard(
                          task: task,
                          onStatusChange: applyTaskStatusChange,
                          onTap: () {
                            Navigator.pop(ctx);
                            showTaskDetailSheet(context, task);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCreateTaskSheet(
  BuildContext context, {
  String? leadId,
  String? leadLabel,
}) {
  final title = leadLabel != null && leadLabel.trim().isNotEmpty
      ? 'Follow up — ${leadLabel.trim()}'
      : leadId != null
          ? 'Follow up — Lead #$leadId'
          : null;
  final description = leadId != null ? 'Lead #$leadId' : null;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddTaskSheet(
      initialTitle: title,
      initialDescription: description,
      linkModule: leadId != null ? 'land_lead:$leadId' : null,
      onSave: (task) async {
        final sync = OfflineSyncService.instance;
        if (!sync.isOnline) {
          await sync.enqueueCreateTask(
            title: task.title,
            description: task.description,
            module: task.module,
            assignedTo: task.assignedTo,
            dueDate: task.dueDate,
            priority: task.priority,
          );
        } else {
          sharedTasks.insert(0, task);
          notifyTaskCreated(task);
        }
        if (context.mounted) {
          if (sync.isOnline) {
            AppFeedback.success(context, 'Task "${task.title}" created');
          } else {
            AppFeedback.warning(context,
                'Task "${task.title}" saved offline — will sync later');
          }
        }
      },
    ),
  );
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum TaskPriority { low, medium, high, urgent }
enum TaskStatus { todo, inProgress, done, overdue }

// ── Static team ───────────────────────────────────────────────────────────────

const _kTeam = [
  'Fomra Admin',
  'Site Manager',
  'Field Agent',
  'Data Analyst',
];

// ── Models ────────────────────────────────────────────────────────────────────

class EscalationRule {
  final int hoursAfterDue;
  final String escalateTo;
  bool triggered;

  EscalationRule({
    required this.hoursAfterDue,
    required this.escalateTo,
    this.triggered = false,
  });
}

class TaskNotification {
  final String id;
  final String taskId;
  final String message;
  final DateTime time;
  bool isRead;

  TaskNotification({
    required this.id,
    required this.taskId,
    required this.message,
    required this.time,
    this.isRead = false,
  });
}

class Task {
  final String id;
  String title;
  String description;
  final TaskPriority priority;
  TaskStatus status;
  final DateTime dueDate;
  final DateTime createdAt;
  DateTime? completedAt;
  List<String> assignedTo;
  String module;
  List<EscalationRule> escalationRules;
  List<Duration> reminderOffsets;
  String notes;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.dueDate,
    required this.createdAt,
    required this.assignedTo,
    required this.module,
    this.completedAt,
    List<EscalationRule>? escalationRules,
    List<Duration>? reminderOffsets,
    this.notes = '',
  })  : escalationRules = escalationRules ?? [],
        reminderOffsets = reminderOffsets ?? [];

  static String generateId() {
    final now = DateTime.now();
    return 'TK-${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 10000}';
  }

  // SLA deadline based on priority
  DateTime get slaDeadline => createdAt.add(_slaDuration(priority));
  bool get isSlaBreached =>
      DateTime.now().isAfter(slaDeadline) && status != TaskStatus.done;
  double get slaProgress {
    final total = slaDeadline.difference(createdAt).inMinutes;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(createdAt).inMinutes;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Duration get slaRemaining => slaDeadline.difference(DateTime.now());

  bool get isOverdue =>
      DateTime.now().isAfter(dueDate) && status != TaskStatus.done;

  int get completionPercent {
    if (status == TaskStatus.done) return 100;
    if (status == TaskStatus.todo) return 0;
    if (status == TaskStatus.overdue) return 0;
    // inProgress: estimate based on time elapsed
    final total = dueDate.difference(createdAt).inMinutes;
    if (total <= 0) return 50;
    final elapsed = DateTime.now().difference(createdAt).inMinutes;
    return (elapsed / total * 80).clamp(10, 90).toInt();
  }
}

Duration _slaDuration(TaskPriority p) => switch (p) {
      TaskPriority.urgent => const Duration(hours: 4),
      TaskPriority.high => const Duration(hours: 24),
      TaskPriority.medium => const Duration(days: 3),
      TaskPriority.low => const Duration(days: 7),
    };

String _slaLabel(TaskPriority p) => switch (p) {
      TaskPriority.urgent => '4h SLA',
      TaskPriority.high => '24h SLA',
      TaskPriority.medium => '3d SLA',
      TaskPriority.low => '7d SLA',
    };

// ── Main Screen ───────────────────────────────────────────────────────────────

class TaskManagementScreen extends StatefulWidget {
  final bool isTab;
  final TaskPortalMode portalMode;
  const TaskManagementScreen({
    super.key,
    this.isTab = false,
    this.portalMode = TaskPortalMode.full,
  });

  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<TaskNotification> _notifications = [];
  String _search = '';

  bool _matchesSearch(Task t) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.description.toLowerCase().contains(q) ||
        t.module.toLowerCase().contains(q) ||
        t.assignedTo.any((a) => a.toLowerCase().contains(q));
  }

  /// Management sees every task; an Executive only sees tasks assigned to them.
  List<Task> get _tasks {
    if (AuthService.instance.isManagement) return sharedTasks;
    final me =
        (AuthService.instance.currentUser?.fullName ?? '').trim().toLowerCase();
    if (me.isEmpty) return sharedTasks;
    return sharedTasks
        .where((t) => t.assignedTo.any((a) => a.trim().toLowerCase() == me))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      animationDuration: Duration.zero,
    );
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Auto-detect overdue on each build
  void _refreshStatuses() {
    for (final t in _tasks) {
      if (t.isOverdue && t.status != TaskStatus.done) {
        if (t.status != TaskStatus.overdue) {
          t.status = TaskStatus.overdue;
          _pushNotification(t, '⚠️ Task "${t.title}" is now overdue.');
        }
        // Check escalation rules
        for (final rule in t.escalationRules) {
          if (!rule.triggered) {
            final overdueBy = DateTime.now().difference(t.dueDate);
            if (overdueBy.inHours >= rule.hoursAfterDue) {
              rule.triggered = true;
              _pushNotification(
                  t,
                  '🔺 Task "${t.title}" escalated to ${rule.escalateTo} '
                  '(overdue by ${rule.hoursAfterDue}h).');
            }
          }
        }
      }
      // Check reminders
      for (final offset in t.reminderOffsets) {
        final reminderTime = t.dueDate.subtract(offset);
        if (DateTime.now().isAfter(reminderTime) &&
            t.status != TaskStatus.done) {
          // Only push once per session (simple check)
          final key = '${t.id}-${offset.inMinutes}';
          if (!_notifications.any((n) => n.id == key)) {
            _pushNotification(t,
                '🔔 Reminder: "${t.title}" is due in ${_offsetLabel(offset)}.',
                id: key);
          }
        }
      }
    }
  }

  /// Apply a task status change and, when an employee makes the change, notify
  /// the management notification bar about the progress.
  void _applyStatusChange(Task task, TaskStatus s) {
    setState(() => applyTaskStatusChange(task, s));
  }

  void _pushNotification(Task task, String message, {String? id}) {
    _notifications.insert(
      0,
      TaskNotification(
        id: id ?? '${task.id}-${DateTime.now().millisecondsSinceEpoch}',
        taskId: task.id,
        message: message,
        time: DateTime.now(),
      ),
    );
  }

  List<Task> _tasksForTab(int index) {
    final base = index == 0
        ? _tasks
        : _tasks
            .where((t) => t.status == [
                  TaskStatus.todo,
                  TaskStatus.inProgress,
                  TaskStatus.done,
                  TaskStatus.overdue
                ][index - 1])
            .toList();
    return base.where(_matchesSearch).toList();
  }

  int get _unread => _notifications.where((n) => !n.isRead).length;

  int _statusCount(TaskStatus status) =>
      _tasks.where((t) => t.status == status).length;

  Widget _buildTaskStatsStrip({bool onPageBg = false}) {
    final stats = [
      ('To Do', _statusCount(TaskStatus.todo), AppColors.textSecondary, Icons.radio_button_unchecked_rounded, 1),
      ('In Progress', _statusCount(TaskStatus.inProgress), AppColors.info, Icons.autorenew_rounded, 2),
      ('Done', _statusCount(TaskStatus.done), AppColors.success, Icons.check_circle_outline_rounded, 3),
      ('Overdue', _statusCount(TaskStatus.overdue), AppColors.error, Icons.warning_amber_rounded, 4),
    ];

    if (onPageBg) {
      return PortalKpiStrip(
        items: stats
            .map(
              (s) => PortalKpiItem(
                label: s.$1,
                value: s.$2,
                icon: s.$4,
                accent: s.$3,
                onTap: () => _tabController.animateTo(s.$5),
              ),
            )
            .toList(),
      );
    }

    final isDark = context.isDarkMode;
    final glass = Colors.white.withValues(alpha: isDark ? 0.08 : 0.14);
    final glassBorder = Colors.white.withValues(alpha: isDark ? 0.12 : 0.16);
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final item = stats[i];
          return InkWell(
            onTap: () => _tabController.animateTo(item.$5),
            borderRadius: BorderRadius.circular(14),
            child: Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.$2}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddTaskFab() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppColors.coloredShadow(AppColors.primary),
        ),
        child: FloatingActionButton.extended(
          onPressed: _openAddTask,
          icon: const Icon(Icons.add_task),
          label: const Text('Add Task'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );

  Widget _buildTaskHeader({bool onPageBg = false}) {
    final isDark = context.isDarkMode;
    final glass = Colors.white.withValues(alpha: isDark ? 0.08 : 0.14);
    final pagePad = FomraLayout.pagePadding(context);

    final tabs = PortalFrostedTabBar(
      controller: _tabController,
      onDarkBackground: !onPageBg,
      tabs: [
        _tabLabel('All', _tasks.length),
        _tabLabel('To Do', _statusCount(TaskStatus.todo)),
        _tabLabel('In Progress', _statusCount(TaskStatus.inProgress)),
        _tabLabel('Done', _statusCount(TaskStatus.done)),
        _tabLabel('Overdue', _statusCount(TaskStatus.overdue)),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: onPageBg ? pagePad.top : 8),
        _buildTaskStatsStrip(onPageBg: onPageBg),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.fromLTRB(
            onPageBg ? 0 : 16,
            0,
            onPageBg ? 0 : 16,
            12,
          ),
          child: onPageBg
              ? tabs
              : Row(children: [
                  Expanded(child: tabs),
                  const SizedBox(width: 8),
                  Stack(clipBehavior: Clip.none, children: [
                    Material(
                      color: glass,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: _showNotificationsSheet,
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.notifications_outlined,
                              color: Colors.white70, size: 19),
                        ),
                      ),
                    ),
                    if (_unread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle),
                          child: Center(
                            child: Text('$_unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ]),
                ]),
        ),
      ],
    );

    if (onPageBg) {
      return Container(
        color: context.fomraPageBg,
        child: portalPageWidthConstraint(
          context,
          Padding(
            padding: pagePad.copyWith(top: 0, bottom: 0),
            child: content,
          ),
        ),
      );
    }

    return content;
  }

  Widget _buildTaskTabBar({bool onPageBg = false}) {
    if (onPageBg) return _buildTaskHeader(onPageBg: true);
    return Container(
      color: context.isDarkMode
          ? const Color(0xFF0F1A2E)
          : AppColors.primaryDark,
      child: _buildTaskHeader(onPageBg: false),
    );
  }

  Future<void> _logout() async {
    final confirmed = await confirmSignOut(context);
    if (!confirmed || !mounted) return;
    AuthService.instance.logout();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  PreferredSizeWidget _portalAppBar(String title) => AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      );

  Widget _buildEmployeePortal() {
    _refreshStatuses();
    final tasks = _tasks;
    return Scaffold(
      appBar: _portalAppBar('My Tasks'),
      body: tasks.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt, size: 48, color: Color(0xFFBDBDBD)),
                  SizedBox(height: 12),
                  Text('No tasks yet',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Tasks assigned by management will appear here',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final task = tasks[i];
                return _TaskCard(
                  task: task,
                  onTap: () => _showTaskDetail(task),
                  onStatusChange: _applyStatusChange,
                );
              },
            ),
    );
  }

  Widget _buildManagementPortal() {
    _refreshStatuses();
    return Scaffold(
      appBar: _portalAppBar('Management · Tasks'),
      floatingActionButton: _buildAddTaskFab(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Material(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _openAddTask,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.add_task,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add New Task',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('Assign work to employees',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textSecondary),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Created tasks (${_tasks.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _tasks.isEmpty
                ? const Center(
                    child: Text('No tasks created yet',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tasks.length,
                    itemBuilder: (_, i) => _TaskCard(
                      task: _tasks[i],
                      onTap: () => _showTaskDetail(_tasks[i]),
                      onStatusChange: (_, __) {},
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.portalMode == TaskPortalMode.employee) {
      return _buildEmployeePortal();
    }
    if (widget.portalMode == TaskPortalMode.management) {
      return _buildManagementPortal();
    }

    _refreshStatuses();

    final taskTabBar = PreferredSize(
      preferredSize: const Size.fromHeight(168),
      child: _buildTaskTabBar(),
    );

    final taskListView = TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        5,
        (i) => _TaskList(
          tasks: _tasksForTab(i),
          tabIndex: i,
          onStatusChange: _applyStatusChange,
          onTap: (task) => _showTaskDetail(task),
          onPrimaryAction: i == 0 ? _openAddTask : null,
          isSearching: _search.trim().isNotEmpty,
        ),
      ),
    );

    final fab = _tabController.index == 0 ? _buildAddTaskFab() : null;

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search tasks by title, module or assignee…',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
          filled: true,
          fillColor: context.fomraSurfaceVar,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );

    if (widget.isTab) {
      return Scaffold(
        backgroundColor: context.fomraPageBg,
        body: Column(children: [
          _buildTaskTabBar(onPageBg: true),
          searchField,
          Expanded(child: taskListView),
        ]),
        floatingActionButton: fab,
      );
    }

    return FomraAppShell(
      currentRoute: '/task-management',
      backgroundColor: context.fomraPageBg,
      appBar: FomraAppBar(
        moduleName: 'Task Management',
        actions: [
          Stack(clipBehavior: Clip.none, children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: _showNotificationsSheet,
            ),
            if (_unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                      color: AppColors.error, shape: BoxShape.circle),
                  child: Center(
                    child: Text('$_unread',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ]),
        ],
        bottom: taskTabBar,
      ),
      body: Column(children: [
        searchField,
        Expanded(child: taskListView),
      ]),
      floatingActionButton: fab,
    );
  }

  Tab _tabLabel(String label, int count) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count', style: const TextStyle(fontSize: 11)),
          ),
        ]),
      );

  void _openAddTask() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTaskSheet(
        onSave: (task) {
          setState(() {
            sharedTasks.insert(0, task);
            _pushNotification(task, '✅ Task "${task.title}" created.');
          });
          notifyTaskCreated(task);
        },
      ),
    );
  }

  void _showTaskDetail(Task task) {
    showTaskDetailSheet(context, task).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(
        notifications: _notifications,
        onMarkAllRead: () => setState(() {
          for (final n in _notifications) {
            n.isRead = true;
          }
        }),
      ),
    );
  }
}

// ── Task List ─────────────────────────────────────────────────────────────────

class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  final int tabIndex;
  final void Function(Task, TaskStatus) onStatusChange;
  final void Function(Task) onTap;
  final VoidCallback? onPrimaryAction;
  final bool isSearching;

  const _TaskList({
    required this.tasks,
    required this.tabIndex,
    required this.onStatusChange,
    required this.onTap,
    this.onPrimaryAction,
    this.isSearching = false,
  });

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 126,
              height: 126,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.13),
                    AppColors.accent.withValues(alpha: 0.07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt_outlined,
                  size: 56,
                  color: AppColors.primary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 18),
            Text(
              isSearching
                  ? 'No matches'
                  : (tabIndex == 0 ? 'No tasks yet' : 'No tasks in this tab'),
              style: TextStyle(
                color: context.fomraTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching
                  ? 'No tasks match your search in this tab.'
                  : (tabIndex == 0
                      ? 'Create your first task to start tracking assignments and progress.'
                      : 'Try another status tab or create a new task to continue.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.fomraTextSecondary,
                fontSize: 13,
              ),
            ),
            if (onPrimaryAction != null && !isSearching) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onPrimaryAction,
                icon: const Icon(Icons.add_task),
                label: const Text('Create Task'),
              ),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return portalPageBody(context, _buildEmptyState(context));
    }
    final pagePad = FomraLayout.pagePadding(context);
    return Align(
      alignment: Alignment.topCenter,
      child: portalPageWidthConstraint(
        context,
        ListView.builder(
          padding: pagePad.copyWith(top: 8, bottom: 96),
          itemCount: tasks.length,
          itemBuilder: (_, i) => PortalFadeSection(
            index: i.clamp(0, 6),
            child: _TaskCard(
              task: tasks[i],
              onStatusChange: onStatusChange,
              onTap: () => onTap(tasks[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Task Card ─────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final Task task;
  final void Function(Task, TaskStatus) onStatusChange;
  final VoidCallback onTap;

  const _TaskCard(
      {required this.task,
      required this.onStatusChange,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pColor = _priorityColor(task.priority);
    final isOverdue = task.status == TaskStatus.overdue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        radius: AppColors.radiusLg,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: pColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppColors.radiusLg),
                  bottomLeft: Radius.circular(AppColors.radiusLg),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(children: [
                      Expanded(
                          child: Text(task.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: task.status == TaskStatus.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ))),
                      const SizedBox(width: 8),
                      _PriorityBadge(priority: task.priority),
                    ]),
                    const SizedBox(height: 3),
                    Text(task.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: context.fomraTextSecondary)),
                    const SizedBox(height: 8),

                    // Completion progress bar
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: task.completionPercent / 100,
                            backgroundColor: context.fomraSurfaceVar,
                            color: task.status == TaskStatus.done
                                ? AppColors.success
                                : task.status == TaskStatus.overdue
                                    ? AppColors.error
                                    : AppColors.info,
                            minHeight: 5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${task.completionPercent}%',
                          style: TextStyle(
                              fontSize: 10,
                              color: context.fomraTextSecondary,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),

                    // SLA bar
                    _SlaBar(task: task),
                    const SizedBox(height: 8),

                    // Assignees + due date row
                    Row(children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          children: task.assignedTo
                              .take(3)
                              .map((name) => _AvatarChip(name: name))
                              .toList(),
                        ),
                      ),
                      Icon(Icons.calendar_today,
                          size: 11,
                          color: isOverdue
                              ? AppColors.error
                              : AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                          '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isOverdue
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontWeight: isOverdue
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ]),

                    // Escalation + reminder indicators
                    if (task.escalationRules.isNotEmpty ||
                        task.reminderOffsets.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, children: [
                        if (task.escalationRules.isNotEmpty)
                          _MicroChip(
                              Icons.escalator_warning,
                              '${task.escalationRules.length} escalation',
                              AppColors.warning),
                        if (task.reminderOffsets.isNotEmpty)
                          _MicroChip(
                              Icons.alarm,
                              '${task.reminderOffsets.length} reminder',
                              AppColors.info),
                        if (task.isSlaBreached)
                          const _MicroChip(
                              Icons.timer_off, 'SLA breached', AppColors.error),
                      ]),
                    ],

                    // Status action buttons — employees update progress;
                    // management only views tasks.
                    if (!AuthService.instance.isManagement) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: TaskStatus.values
                                .where((s) => s != task.status)
                                .map((s) => Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            onStatusChange(task, s),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          side: BorderSide(
                                              color: _statusColor(s)
                                                  .withValues(alpha: 0.5)),
                                        ),
                                        child: Text('→ ${_statusLabel(s)}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: _statusColor(s))),
                                      ),
                                    ))
                                .toList()),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── SLA Bar ───────────────────────────────────────────────────────────────────

class _SlaBar extends StatelessWidget {
  final Task task;
  const _SlaBar({required this.task});

  @override
  Widget build(BuildContext context) {
    final progress = task.slaProgress;
    final breached = task.isSlaBreached;
    final done = task.status == TaskStatus.done;
    final color =
        done ? AppColors.success : breached ? AppColors.error : _slaColor(progress);
    final label = done
        ? 'SLA met'
        : breached
            ? 'SLA breached'
            : _slaRemainingLabel(task.slaRemaining);

    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: context.fomraSurfaceVar,
            color: color,
            minHeight: 4,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${_slaLabel(task.priority)} · $label',
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Color _slaColor(double p) {
    if (p < 0.6) return AppColors.success;
    if (p < 0.85) return AppColors.warning;
    return AppColors.error;
  }

  String _slaRemainingLabel(Duration d) {
    if (d.isNegative) return 'breached';
    if (d.inDays > 0) return '${d.inDays}d left';
    if (d.inHours > 0) return '${d.inHours}h left';
    return '${d.inMinutes}m left';
  }
}

// ── Add Task Sheet ────────────────────────────────────────────────────────────

class _AddTaskSheet extends StatefulWidget {
  final void Function(Task) onSave;
  final String? initialTitle;
  final String? initialDescription;
  final String? linkModule;

  const _AddTaskSheet({
    required this.onSave,
    this.initialTitle,
    this.initialDescription,
    this.linkModule,
  });

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  TaskPriority _priority = TaskPriority.medium;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 3));
  final Set<String> _assignedTo = {};
  final Set<Duration> _reminders = {};

  /// Selectable assignees — real employee roster when available, else _kTeam.
  List<String> _teamNames = List<String>.from(_kTeam);

  bool get _isManagement => AuthService.instance.isManagement;
  late final AnimationController _enterCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle != null) {
      _titleCtrl.text = widget.initialTitle!;
    }
    if (widget.initialDescription != null) {
      _descCtrl.text = widget.initialDescription!;
    }
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(_fade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterCtrl.forward());
    if (_isManagement) _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    // Use already-loaded roster immediately if present.
    final cached = AppStore.instance.employees;
    if (cached.isNotEmpty) {
      setState(() => _teamNames = _namesFrom(cached));
      return;
    }
    try {
      final list = await EmployeeService.getAll();
      if (list.isNotEmpty) AppStore.instance.setEmployees(list);
      if (mounted && list.isNotEmpty) {
        setState(() => _teamNames = _namesFrom(list));
      }
    } catch (_) {
      // Keep the _kTeam fallback on failure.
    }
  }

  List<String> _namesFrom(List<EmployeeProfile> list) {
    final active =
        list.where((e) => e.status == EmployeeStatus.active).toList();
    final src = active.isNotEmpty ? active : list;
    return src.map((e) => e.fullName).toList();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.96,
      minChildSize: 0.6,
      expand: false,
      builder: (_, controller) => FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              decoration: BoxDecoration(
                color: context.fomraSurface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(children: [
                _SheetHandle(),
                _buildHeader(context),
                Divider(height: 1, color: context.fomraBorder),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(20),
                      children: [
                        _FormSectionCard(
                          icon: Icons.edit_note_rounded,
                          title: 'General',
                          child: Column(
                            children: [
                              const _SectionLabel('Task Title'),
                              TextFormField(
                                controller: _titleCtrl,
                                decoration: _dec(context, 'Enter task title'),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              const _SectionLabel('Description'),
                              TextFormField(
                                controller: _descCtrl,
                                decoration: _dec(
                                  context,
                                  'Briefly describe the expected outcome',
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 14),
                              const _SectionLabel('Priority'),
                              _buildPriorityChips(context),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FormSectionCard(
                          icon: Icons.schedule_rounded,
                          title: 'Schedule',
                          child: Column(
                            children: [
                              const _SectionLabel('Due Date'),
                              _buildDueDateField(context),
                              const SizedBox(height: 16),
                              const _SectionLabel('Reminder System'),
                              _buildReminderChips(context),
                            ],
                          ),
                        ),
                        if (_isManagement) ...[
                          const SizedBox(height: 16),
                          _FormSectionCard(
                            icon: Icons.group_outlined,
                            title: 'Assignment',
                            child: Column(
                              children: [
                                const _SectionLabel('Assign Users'),
                                _buildAssigneeDropdown(context),
                                if (_assignedTo.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _assignedTo.map((name) {
                                      return Chip(
                                        label: Text(name,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white)),
                                        avatar: CircleAvatar(
                                          backgroundColor:
                                              Colors.white.withValues(alpha: 0.3),
                                          child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                        backgroundColor: AppColors.primary,
                                        side:
                                            const BorderSide(color: AppColors.primary),
                                        deleteIcon: const Icon(Icons.close,
                                            size: 16, color: Colors.white),
                                        onDeleted: () => setState(
                                            () => _assignedTo.remove(name)),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _FormSectionCard(
                          icon: Icons.notes_rounded,
                          title: 'Notes',
                          child: Column(
                            children: [
                              const _SectionLabel('Additional Notes'),
                              TextFormField(
                                controller: _notesCtrl,
                                decoration: _dec(context, 'Optional details…'),
                                maxLines: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                _buildFooter(context),
              ]),
            ),
          ),
        ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Task',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                  ),
                ),
                Text(
                  'Assign work with priorities, due dates and reminders.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityChips(BuildContext context) {
    final options = [
      (TaskPriority.low, 'Low', AppColors.success),
      (TaskPriority.medium, 'Medium', AppColors.info),
      (TaskPriority.high, 'High', AppColors.warning),
      (TaskPriority.urgent, 'Urgent', AppColors.error),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((entry) {
        final selected = _priority == entry.$1;
        return ChoiceChip(
          label: Text(entry.$2),
          selected: selected,
          showCheckmark: false,
          avatar: Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: entry.$3, shape: BoxShape.circle),
          ),
          selectedColor: entry.$3.withValues(alpha: 0.18),
          backgroundColor: context.fomraSurfaceVar,
          side: BorderSide(
            color: selected ? entry.$3 : context.fomraBorder,
          ),
          labelStyle: TextStyle(
            color: selected ? entry.$3 : context.fomraTextPrimary,
            fontWeight: FontWeight.w700,
          ),
          onSelected: (_) => setState(() => _priority = entry.$1),
        );
      }).toList(),
    );
  }

  Widget _buildDueDateField(BuildContext context) {
    final now = DateTime.now();
    final dueIn = _dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    return InkWell(
      onTap: _pickDueDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar,
          border: Border.all(color: context.fomraBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded,
                size: 20,
                color: context.isDarkMode
                    ? AppColors.primaryLight
                    : AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueIn < 0
                        ? 'Due date passed'
                        : dueIn == 0
                            ? 'Due today'
                            : 'Due in $dueIn day${dueIn == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _slaLabel(_priority),
              style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kReminderOptions.entries.map((e) {
        final selected = _reminders.contains(e.value);
        return FilterChip(
          label: Text(e.key,
              style: TextStyle(
                  fontSize: 12,
                  color: selected || context.isDarkMode
                      ? Colors.white
                      : context.fomraTextPrimary)),
          selected: selected,
          onSelected: (v) => setState(
              () => v ? _reminders.add(e.value) : _reminders.remove(e.value)),
          selectedColor: AppColors.info,
          backgroundColor: context.fomraSurfaceVar,
          side:
              BorderSide(color: selected ? AppColors.info : context.fomraBorder),
          avatar: Icon(Icons.alarm,
              size: 14, color: selected ? Colors.white : AppColors.info),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.fomraSurface,
        border: Border(top: BorderSide(color: context.fomraBorder)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(96, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Create Task'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeDropdown(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.fomraSurface),
        elevation: const WidgetStatePropertyAll(4),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.fomraBorder),
        )),
      ),
      builder: (context, controller, _) {
        return InkWell(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar,
              border: Border.all(color: context.fomraBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Icon(Icons.group_outlined,
                  size: 18,
                  color: context.isDarkMode
                      ? AppColors.primaryLight
                      : AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _assignedTo.isEmpty
                      ? 'Select employees…'
                      : '${_assignedTo.length} selected',
                  style: TextStyle(
                      fontSize: 14,
                      color: _assignedTo.isEmpty
                          ? context.fomraTextSecondary
                          : context.fomraTextPrimary),
                ),
              ),
              Icon(
                  controller.isOpen
                      ? Icons.arrow_drop_up
                      : Icons.arrow_drop_down,
                  color: context.fomraTextSecondary),
            ]),
          ),
        );
      },
      menuChildren: [
        for (final name in _teamNames) _buildAssigneeMenuItem(context, name),
      ],
    );
  }

  Widget _buildAssigneeMenuItem(BuildContext context, String name) {
    final selected = _assignedTo.contains(name);
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: () => setState(() =>
          selected ? _assignedTo.remove(name) : _assignedTo.add(name)),
      leadingIcon: Icon(
        selected ? Icons.check_box : Icons.check_box_outline_blank,
        size: 20,
        color: selected ? AppColors.primary : context.fomraTextSecondary,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(name,
              style: TextStyle(fontSize: 14, color: context.fomraTextPrimary)),
        ],
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final task = Task(
      id: Task.generateId(),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      priority: _priority,
      status: TaskStatus.todo,
      dueDate: _dueDate,
      createdAt: DateTime.now(),
      assignedTo: _isManagement ? _assignedTo.toList() : const [],
      module: widget.linkModule ?? '',
      escalationRules: const [],
      reminderOffsets: _reminders.toList(),
      notes: _notesCtrl.text.trim(),
    );
    widget.onSave(task);
    Navigator.pop(context);
  }
}

// ── Task Detail Sheet ─────────────────────────────────────────────────────────

class _TaskDetailSheet extends StatelessWidget {
  final Task task;
  final void Function(TaskStatus) onStatusChange;

  const _TaskDetailSheet(
      {required this.task, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: context.fomraSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              Expanded(
                  child: Text(task.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700))),
              _PriorityBadge(priority: task.priority),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                // Status actions — hidden for management (view-only).
                if (!AuthService.instance.isManagement) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: TaskStatus.values.map((s) {
                    final active = task.status == s;
                    return GestureDetector(
                      onTap: () {
                        onStatusChange(s);
                        Navigator.pop(context);
                      },
                      child: Column(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: active
                                ? _statusColor(s)
                                : _statusColor(s).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_statusIcon(s),
                              color: active
                                  ? Colors.white
                                  : _statusColor(s),
                              size: 20),
                        ),
                        const SizedBox(height: 4),
                        Text(_statusLabel(s),
                            style: TextStyle(
                                fontSize: 10,
                                color: active
                                    ? _statusColor(s)
                                    : AppColors.textSecondary,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.normal)),
                      ]),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ],

                // Track Completion
                _DetailSection(
                  icon: Icons.track_changes,
                  title: 'Track Completion',
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: task.completionPercent / 100,
                            backgroundColor: const Color(0xFFE5E7EB),
                            color: task.status == TaskStatus.done
                                ? AppColors.success
                                : AppColors.info,
                            minHeight: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${task.completionPercent}%',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ]),
                    if (task.completedAt != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.check_circle,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(
                            'Completed on ${task.completedAt!.day}/${task.completedAt!.month}/${task.completedAt!.year}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.success)),
                      ]),
                    ],
                  ]),
                ),

                // SLA Tracking
                _DetailSection(
                  icon: Icons.timer_outlined,
                  title: 'SLA Tracking',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SlaBar(task: task),
                        const SizedBox(height: 8),
                        Row(children: [
                          _InfoPill(
                              'SLA',
                              _slaLabel(task.priority),
                              AppColors.primary),
                          const SizedBox(width: 8),
                          _InfoPill(
                              'Created',
                              '${task.createdAt.day}/${task.createdAt.month}/${task.createdAt.year}',
                              AppColors.textSecondary),
                          const SizedBox(width: 8),
                          _InfoPill(
                              'Deadline',
                              '${task.slaDeadline.day}/${task.slaDeadline.month} '
                                  '${task.slaDeadline.hour.toString().padLeft(2, '0')}:${task.slaDeadline.minute.toString().padLeft(2, '0')}',
                              task.isSlaBreached
                                  ? AppColors.error
                                  : AppColors.success),
                        ]),
                      ]),
                ),

                // Assigned Users
                if (task.assignedTo.isNotEmpty)
                  _DetailSection(
                    icon: Icons.group_outlined,
                    title: 'Assigned Users',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: task.assignedTo
                          .map((name) => _AvatarChip(name: name, large: true))
                          .toList(),
                    ),
                  ),

                // Escalation Rules
                _DetailSection(
                  icon: Icons.escalator_warning,
                  title: 'Escalation Rules',
                  child: task.escalationRules.isEmpty
                      ? const Text('No escalation rules.',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary))
                      : Column(
                          children: task.escalationRules
                              .map((r) => _EscalationTile(rule: r))
                              .toList()),
                ),

                // Reminder System
                _DetailSection(
                  icon: Icons.alarm,
                  title: 'Reminder System',
                  child: task.reminderOffsets.isEmpty
                      ? const Text('No reminders set.',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: task.reminderOffsets
                              .map((d) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.info
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.alarm,
                                              size: 12,
                                              color: AppColors.info),
                                          const SizedBox(width: 5),
                                          Text(_offsetLabel(d),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.info,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ]),
                                  ))
                              .toList(),
                        ),
                ),

                // Description + Notes
                if (task.description.isNotEmpty)
                  _DetailSection(
                    icon: Icons.description_outlined,
                    title: 'Description',
                    child: Text(task.description,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5)),
                  ),
                if (task.notes.isNotEmpty)
                  _DetailSection(
                    icon: Icons.notes,
                    title: 'Notes',
                    child: Text(task.notes,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5)),
                  ),

                if (task.module.isNotEmpty)
                  _DetailSection(
                    icon: Icons.folder_outlined,
                    title: 'Module',
                    child: Text(task.module,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Notifications Sheet ───────────────────────────────────────────────────────

class _NotificationsSheet extends StatelessWidget {
  final List<TaskNotification> notifications;
  final VoidCallback onMarkAllRead;

  const _NotificationsSheet(
      {required this.notifications, required this.onMarkAllRead});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: context.fomraSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              const Text('Notifications',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (notifications.isNotEmpty)
                TextButton(
                  onPressed: () {
                    onMarkAllRead();
                    Navigator.pop(context);
                  },
                  child: const Text('Mark all read',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: notifications.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.notifications_none,
                          size: 34,
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    const SizedBox(height: 12),
                    const Text('No notifications yet.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                  ]))
                : ListView.separated(
                    controller: controller,
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = notifications[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.task_alt,
                              size: 16, color: AppColors.primary),
                        ),
                        title: Text(n.message,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: n.isRead
                                    ? FontWeight.normal
                                    : FontWeight.w600)),
                        subtitle: Text(
                            _timeAgo(n.time),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                        trailing: n.isRead
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle),
                              ),
                        tileColor: n.isRead
                            ? null
                            : AppColors.primary.withValues(alpha: 0.03),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.fomraBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _FormSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _FormSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      interactive: false,
      radius: AppColors.radiusMd,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.fomraTextSecondary,
                letterSpacing: 0.3)),
      );
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _DetailSection(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.3)),
          ]),
          const SizedBox(height: 10),
          child,
          const SizedBox(height: 14),
          const Divider(height: 1),
        ]),
      );
}

class _EscalationTile extends StatelessWidget {
  final EscalationRule rule;

  const _EscalationTile({required this.rule});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(
              rule.triggered
                  ? Icons.check_circle
                  : Icons.escalator_warning,
              size: 15,
              color: rule.triggered
                  ? AppColors.error
                  : AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
            'After ${rule.hoursAfterDue}h overdue → ${rule.escalateTo}',
            style: TextStyle(fontSize: 12, color: context.fomraTextPrimary),
          )),
          if (rule.triggered)
            const _MicroChip(Icons.warning, 'Triggered', AppColors.error),
        ]),
      );
}

class _AvatarChip extends StatelessWidget {
  final String name;
  final bool large;
  const _AvatarChip({required this.name, this.large = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: large ? 10 : 8,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            child: Text(name[0],
                style: TextStyle(
                    fontSize: large ? 10 : 8,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 5),
          Text(name,
              style: TextStyle(
                  fontSize: large ? 13 : 10,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _MicroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MicroChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _PriorityBadge extends StatelessWidget {
  final TaskPriority priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20)),
      child: Text(_priorityLabel(priority),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kReminderOptions = {
  '30 min before': Duration(minutes: 30),
  '1 hour before': Duration(hours: 1),
  '3 hours before': Duration(hours: 3),
  '1 day before': Duration(days: 1),
  '2 days before': Duration(days: 2),
};

String _offsetLabel(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d before';
  if (d.inHours >= 1) return '${d.inHours}h before';
  return '${d.inMinutes}m before';
}

Color _priorityColor(TaskPriority p) => switch (p) {
      TaskPriority.low => AppColors.success,
      TaskPriority.medium => AppColors.info,
      TaskPriority.high => AppColors.warning,
      TaskPriority.urgent => AppColors.error,
    };

String _priorityLabel(TaskPriority p) => switch (p) {
      TaskPriority.low => 'LOW',
      TaskPriority.medium => 'MED',
      TaskPriority.high => 'HIGH',
      TaskPriority.urgent => 'URGENT',
    };

Color _statusColor(TaskStatus s) => switch (s) {
      TaskStatus.todo => AppColors.textSecondary,
      TaskStatus.inProgress => AppColors.info,
      TaskStatus.done => AppColors.success,
      TaskStatus.overdue => AppColors.error,
    };

String _statusLabel(TaskStatus s) => switch (s) {
      TaskStatus.todo => 'To Do',
      TaskStatus.inProgress => 'In Progress',
      TaskStatus.done => 'Done',
      TaskStatus.overdue => 'Overdue',
    };

IconData _statusIcon(TaskStatus s) => switch (s) {
      TaskStatus.todo => Icons.radio_button_unchecked,
      TaskStatus.inProgress => Icons.pending_outlined,
      TaskStatus.done => Icons.check_circle_outline,
      TaskStatus.overdue => Icons.warning_amber_outlined,
    };

InputDecoration _dec(BuildContext context, String? hint) =>
    FomraInput.decoration(context: context, hint: hint);
