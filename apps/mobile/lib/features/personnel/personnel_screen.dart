import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/personnel_picker.dart';
import '../../core/private_screen.dart';
import '../groups/team_home_screen.dart';

class PersonnelScreen extends ConsumerStatefulWidget {
  const PersonnelScreen({super.key});
  @override
  ConsumerState<PersonnelScreen> createState() => _PersonnelScreenState();
}

class _PersonnelScreenState extends ConsumerState<PersonnelScreen>
    with WidgetsBindingObserver {
  String? team, owner;
  List<Json> records = [];
  bool busy = false;
  String? error;
  int generation = 0;
  final privacy = PrivateScreenGuard();
  @override
  void initState() {
    super.initState();
    privacy.open();
    owner = ref.read(appProvider).user?['id'];
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    generation++;
    privacy.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed) {
      generation++;
      if (mounted) {
        setState(() {
          records = [];
          busy = false;
        });
      }
    } else if (team != null) {
      _load();
    }
  }

  Future<void> _load() async {
    if (team == null) return;
    final ticket = ++generation, id = team;
    setState(() {
      busy = true;
      error = null;
      records = [];
    });
    try {
      final result = jsonList(
        await ref.read(appProvider.notifier).api.get('/groups/$id/workers'),
      );
      if (mounted &&
          ticket == generation &&
          owner == ref.read(appProvider).user?['id']) {
        setState(() => records = result);
      }
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() => error = ApiClient.describe(e));
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<void> _edit(Json? record) async {
    if (team == null) return;
    final app = ref.read(appProvider.notifier);
    final group = ref
        .read(appProvider)
        .groups
        .where((g) => g['id'] == team)
        .firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkerEditor(
          team: team!,
          record: record,
          members: jsonList(group?['members']),
        ),
      ),
    );
    if (mounted) {
      _load();
      await app.sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    ref.listen(appProvider, (before, after) {
      if (after.user?['id'] != owner ||
          (team != null &&
              !after.groups.any(
                (g) => g['id'] == team && g['role'] == 'admin',
              ))) {
        generation++;
        if (mounted) {
          setState(() {
            records = [];
            team = null;
          });
        }
      }
    });
    final teams = state.groups.where((g) => g['role'] == 'admin').toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Team member records',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        const Text(
          'Team admins maintain these records. Salary, payments and identity images stay private to admins.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        if (teams.isEmpty)
          const EmptyState(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Team admins only',
            description:
                'Create a team or ask its admin to manage member records.',
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: teams.any((g) => g['id'] == team) ? team : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Choose a team'),
            items: teams
                .map(
                  (g) => DropdownMenuItem<String>(
                    value: g['id'],
                    child: Text(g['name']),
                  ),
                )
                .toList(),
            onChanged: (v) {
              team = v;
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (team != null)
            FilledButton.icon(
              onPressed: busy ? null : () => _edit(null),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add member record'),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.deepOrange)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
          if (team != null && !busy && error == null && records.isEmpty)
            const EmptyState(
              icon: Icons.badge_outlined,
              title: 'No member records yet',
              description: 'Add a member record, then link it to their account after they join your team.',
            ),
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Surface(
                padding: const EdgeInsets.all(4),
                child: ListTile(
                  leading: MemberAvatar(member: record),
                  title: Text(memberDisplayName(record['displayName'])),
                  subtitle: Text(
                    '${record['jobTitle']} · ${record['linkedUserId'] == null ? 'Account not linked' : 'Account linked'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(record),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class WorkerEditor extends ConsumerStatefulWidget {
  final String team;
  final Json? record;
  final List<Json> members;
  const WorkerEditor({
    super.key,
    required this.team,
    this.record,
    required this.members,
  });
  @override
  ConsumerState<WorkerEditor> createState() => _WorkerEditorState();
}

class _WorkerEditorState extends ConsumerState<WorkerEditor>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  Json? record;
  String? linked, photo, owner;
  String period = 'month', status = 'active';
  bool consent = false, busy = false, foreground = true;
  Uint8List? document;
  Completer<void>? _resume;
  Future<void> _awaitForeground() async {
    if (foreground || !mounted) return;
    _resume ??= Completer<void>();
    await _resume!.future.timeout(const Duration(seconds: 30));
  }

  int generation = 0;
  final privacy = PrivateScreenGuard();
  ApiClient get api => ref.read(appProvider.notifier).api;
  String get path =>
      '/groups/${widget.team}/workers${record == null ? '' : '/${record!['id']}'}';
  @override
  void initState() {
    super.initState();
    privacy.open();
    WidgetsBinding.instance.addObserver(this);
    owner = ref.read(appProvider).user?['id'];
    record = widget.record == null ? null : Json.from(widget.record!);
    fields = {
      for (final key in [
        'displayName',
        'phone',
        'jobTitle',
        'site',
        'joinedDate',
        'workDetails',
        'salaryAmount',
      ])
        key: TextEditingController(
          text:
              record?[key]?.toString() ??
              (key == 'joinedDate'
                  ? DateTime.now().toIso8601String().substring(0, 10)
                  : key == 'salaryAmount'
                  ? '0'
                  : ''),
        ),
    };
    linked = record?['linkedUserId'];
    photo = record?['photoData'];
    period = record?['salaryPeriod'] ?? 'month';
    status = record?['status'] ?? 'active';
    consent = record != null;
  }

  @override
  void dispose() {
    generation++;
    privacy.close();
    if (_resume?.isCompleted == false) _resume!.complete();
    for (final c in fields.values) {
      c.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (foreground) {
      if (_resume?.isCompleted == false) _resume!.complete();
      _resume = null;
    }
    if (!foreground) {
      generation++;
      if (mounted) {
        setState(() {
          document = null;
          busy = false;
        });
      }
    } else if (record != null) {
      _refresh();
    }
  }

  bool valid(int ticket) =>
      mounted &&
      ticket == generation &&
      foreground &&
      owner == ref.read(appProvider).user?['id'];
  Future<void> _refresh() async {
    final ticket = ++generation;
    try {
      final result = Json.from(await api.get(path));
      if (mounted && valid(ticket)) setState(() => record = result);
    } catch (e) {
      if (mounted && valid(ticket)) {
        notice(context, ApiClient.describe(e));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _action(Future<void> Function(int) task) async {
    if (busy) return;
    final ticket = ++generation;
    setState(() => busy = true);
    try {
      await task(ticket);
    } catch (e) {
      if (mounted && valid(ticket)) notice(context, ApiClient.describe(e));
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<void> _save() => _action((ticket) async {
    if (!form.currentState!.validate()) return;
    if (!consent) {
      throw Exception(
        'Record the member’s permission before saving personal information.',
      );
    }
    final phone = fields['phone']!.text.replaceAll(RegExp(r'[\s()-]'), '');
    final input = <String, dynamic>{
      for (final entry in fields.entries) entry.key: entry.value.text.trim(),
      'phone': RegExp(r'^\d{10}$').hasMatch(phone) ? '+91$phone' : phone,
      'salaryAmount': double.parse(fields['salaryAmount']!.text),
      'salaryPeriod': period,
      'status': status,
      'consent': true,
      'photoData': photo ?? '',
      if (linked != null) 'linkedUserId': linked,
    };
    final result = Json.from(
      record == null
          ? await api.post(path, input)
          : await api.patch(path, input),
    );
    if (mounted && valid(ticket)) {
      setState(() => record = result);
      notice(context, 'Member record saved.');
    }
  });
  Future<void> _photo() async {
    try {
      final result = await pickPersonnelImage(profile: true);
      await _awaitForeground();
      if (mounted &&
          owner == ref.read(appProvider).user?['id'] &&
          result != null) {
        setState(
          () => photo = 'data:${result['mimeType']};base64,${result['base64']}',
        );
      }
    } catch (e) {
      if (mounted) notice(context, ApiClient.describe(e));
    }
  }

  Future<void> _documentUpload() async {
    if (record == null) return;
    final recordId = record!['id'];
    if (!await confirmAction(
      context,
      'Upload identity photo?',
      'Confirm that this member has agreed to store their Aadhaar or identity image for manual review by team admins.',
      action: 'Choose photo',
    )) {
      return;
    }
    try {
      final result = await pickPersonnelImage();
      await _awaitForeground();
      if (!mounted ||
          owner != ref.read(appProvider).user?['id'] ||
          result == null) {
        return;
      }
      await _action((ticket) async {
        await api.post('/groups/${widget.team}/workers/$recordId/document', {
          ...result,
          'consent': true,
        });
        final updated = Json.from(
          await api.get('/groups/${widget.team}/workers/$recordId'),
        );
        if (mounted && valid(ticket)) {
          setState(() => record = updated);
          notice(context, 'Identity photo uploaded for manual review.');
        }
      });
    } catch (e) {
      if (mounted) notice(context, ApiClient.describe(e));
    }
  }

  Future<void> _entry(bool payment) async {
    if (record == null) return;
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => _EntryDialog(payment: payment),
    );
    if (result == null || !mounted) return;
    await _action((ticket) async {
      final updated = Json.from(
        await api.post('$path/${payment ? 'payments' : 'work'}', result),
      );
      if (mounted && valid(ticket)) setState(() => record = updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider, (before, after) {
      if ((after.user?['id'] != owner ||
              !after.groups.any(
                (g) => g['id'] == widget.team && g['role'] == 'admin',
              )) &&
          mounted) {
        generation++;
        document = null;
        Navigator.pop(context);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(record == null ? 'Add member record' : 'Member record'),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: MemberAvatar(
                      member: {
                        'displayName': fields['displayName']!.text,
                        'photoData': photo,
                      },
                      radius: 40,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _photo,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add / change profile photo'),
                  ),
                  if (photo?.isNotEmpty == true)
                    TextButton(
                      onPressed: () => setState(() => photo = ''),
                      child: const Text('Remove profile photo'),
                    ),
                  for (final field in [
                    ('displayName', 'Member name'),
                    ('phone', 'Phone (optional)'),
                    ('jobTitle', 'Job / role'),
                    ('site', 'Site / location'),
                    ('joinedDate', 'Joined date · YYYY-MM-DD'),
                    ('workDetails', 'Work details'),
                    ('salaryAmount', 'Salary amount · INR'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: fields[field.$1],
                        keyboardType: field.$1 == 'salaryAmount'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : field.$1 == 'phone'
                            ? TextInputType.phone
                            : TextInputType.text,
                        maxLength: field.$1 == 'workDetails'
                            ? 2000
                            : field.$1 == 'displayName' ||
                                  field.$1 == 'jobTitle'
                            ? 80
                            : field.$1 == 'site'
                            ? 100
                            : 30,
                        maxLines: field.$1 == 'workDetails' ? 3 : 1,
                        decoration: InputDecoration(labelText: field.$2),
                        validator: (v) {
                          if (field.$1 == 'displayName' &&
                              (v?.trim().length ?? 0) < 2) {
                            return 'Enter a name with at least two characters';
                          }
                          if (field.$1 == 'salaryAmount' &&
                              (double.tryParse(v ?? '') == null ||
                                  double.parse(v!) < 0)) {
                            return 'Enter a valid amount';
                          }
                          if (field.$1 == 'joinedDate' &&
                              (DateTime.tryParse(v ?? '') == null ||
                                  !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                      .hasMatch(v ?? ''))) {
                            return 'Use YYYY-MM-DD';
                          }
                          return null;
                        },
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: period,
                    decoration: const InputDecoration(
                      labelText: 'Salary period',
                    ),
                    items: ['day', 'week', 'month']
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text('Per $v')),
                        )
                        .toList(),
                    onChanged: (v) => period = v!,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Work status'),
                    items:
                        [
                              ('active', 'Active'),
                              ('on_leave', 'On leave'),
                              ('left', 'Left'),
                            ]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v.$1,
                                child: Text(v.$2),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => status = v!,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue:
                        widget.members.any((m) => m['userId'] == linked)
                        ? linked ?? ''
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Link to team account',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Not linked · invite member first'),
                      ),
                      ...widget.members.map(
                        (m) => DropdownMenuItem<String>(
                          value: m['userId'],
                          child: Text(memberDisplayName(m['displayName'])),
                        ),
                      ),
                    ],
                    onChanged: (v) => linked = v?.isEmpty == true ? null : v,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: const Text('Member agreed to store these details'),
                    subtitle: const Text(
                      'Profile photo, joining date and work summary are visible within the team. Salary, payments, work logs and identity images are admin-only.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(busy ? 'Saving…' : 'Save member details'),
                  ),
                ],
              ),
            ),
            if (record != null && foreground) ...[
              const SizedBox(height: 24),
              Text(
                'Identity photo · private',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Aadhaar or another identity image for manual review. Uploading a photo does not perform Aadhaar verification.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              OutlinedButton.icon(
                onPressed: _documentUpload,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  record!['identityDocumentId'] == null
                      ? 'Upload identity photo'
                      : 'Replace identity photo',
                ),
              ),
              if (record!['identityDocumentId'] != null) ...[
                TextButton(
                  onPressed: () => _action((ticket) async {
                    final data = Json.from(await api.get('$path/document'));
                    if (mounted && valid(ticket)) {
                      setState(() => document = base64Decode(data['base64']));
                    }
                  }),
                  child: const Text('View private photo'),
                ),
                TextButton(
                  onPressed: () => _action((ticket) async {
                    await api.delete('$path/document');
                    if (mounted && valid(ticket)) {
                      setState(() {
                        record!.remove('identityDocumentId');
                        document = null;
                      });
                    }
                  }),
                  child: const Text('Delete identity photo'),
                ),
              ],
              if (document != null) ...[
                Image.memory(document!, height: 260, fit: BoxFit.contain),
                TextButton(
                  onPressed: () => setState(() => document = null),
                  child: const Text('Hide photo'),
                ),
              ],
              const Divider(height: 32),
              Text(
                'Salary payments · INR',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              OutlinedButton.icon(
                onPressed: () => _entry(true),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
              for (final p in jsonList(record!['payments']).reversed)
                ListTile(
                  title: Text('₹${p['amount']} · ${p['date']}'),
                  subtitle: Text(p['note'] ?? ''),
                  trailing: IconButton(
                    tooltip: 'Delete payment entry',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeEntry('payments', p['id']),
                  ),
                ),
              const Divider(height: 32),
              Text('Work log', style: Theme.of(context).textTheme.titleLarge),
              OutlinedButton.icon(
                onPressed: () => _entry(false),
                icon: const Icon(Icons.work_outline),
                label: const Text('Record work'),
              ),
              for (final p in jsonList(record!['workLog']).reversed)
                ListTile(
                  title: Text('${p['date']} · ${p['hours']} hours'),
                  subtitle: Text(p['detail'] ?? ''),
                  trailing: IconButton(
                    tooltip: 'Delete work entry',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeEntry('work', p['id']),
                  ),
                ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () async {
                  if (!await confirmAction(
                    context,
                    'Delete member record?',
                    'This removes the record, salary payments, work log and identity photo. Team membership remains.',
                    action: 'Delete',
                  )) {
                    return;
                  }
                  await _action((ticket) async {
                    await api.delete(path);
                    if (context.mounted && valid(ticket)) {
                      Navigator.pop(context);
                    }
                  });
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete member record'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _removeEntry(String kind, String id) async {
    if (!await confirmAction(
      context,
      'Delete this entry?',
      'Remove this ${kind == 'payments' ? 'payment' : 'work'} record?',
      action: 'Delete',
    )) {
      return;
    }
    await _action((ticket) async {
      final updated = Json.from(await api.delete('$path/$kind/$id'));
      if (mounted && valid(ticket)) setState(() => record = updated);
    });
  }
}

class _EntryDialog extends StatefulWidget {
  final bool payment;
  const _EntryDialog({required this.payment});
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final form = GlobalKey<FormState>(),
      date = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10),
      ),
      amount = TextEditingController(),
      note = TextEditingController();
  @override
  void dispose() {
    date.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.payment ? 'Record payment' : 'Record work'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: date,
              decoration: const InputDecoration(labelText: 'Date · YYYY-MM-DD'),
              validator: (v) =>
                  DateTime.tryParse(v ?? '') == null ? 'Enter a date' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: widget.payment ? 'Amount · INR' : 'Hours · 0 to 24',
              ),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null ||
                        n < (widget.payment ? .01 : 0) ||
                        n > (widget.payment ? 10000000 : 24)
                    ? 'Enter a valid value'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: note,
              maxLength: widget.payment ? 500 : 1000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.payment ? 'Payment note' : 'Work done',
              ),
              validator: (v) => !widget.payment && (v?.trim().isEmpty ?? true)
                  ? 'Describe the work'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              'date': date.text.trim(),
              widget.payment ? 'amount' : 'hours': double.parse(amount.text),
              widget.payment ? 'note' : 'detail': note.text.trim(),
            });
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}
