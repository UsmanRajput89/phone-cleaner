import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;

import '../app/controller.dart';
import '../app/theme.dart';
import 'soft.dart';

/// Lets the user choose an existing Safe folder or create a new one.
/// Returns the folder path, or null if cancelled.
Future<String?> pickSafeFolder(BuildContext context) {
  final p = context.soft;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _FolderSheet(),
  );
}

class _FolderSheet extends StatefulWidget {
  const _FolderSheet();

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  List<String>? _folders;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final list = await c.listSafeFolders();
    if (!mounted) return;
    setState(() => _folders = list);
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !mounted) return;
    final c = AppScope.read(context);
    final path = await c.createSafeFolder(name);
    if (!mounted) return;
    if (path == null) {
      showSoftSnack(context, 'That name is not usable');
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final folders = _folders;
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Move to folder', style: ts(context, 22)),
              const SizedBox(height: 4),
              Text('Folders live in Safe/ and show up as Gallery albums.',
                  style: ts(context, 12, color: p.muted)),
              const SizedBox(height: 16),
              SoftPill(
                label: 'New folder',
                icon: Icons.create_new_folder_outlined,
                onTap: _create,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: folders == null
                    ? Center(child: CircularProgressIndicator(color: p.accent))
                    : folders.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('No folders yet',
                                style: ts(context, 14, color: p.muted)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: folders.length,
                            itemBuilder: (context, i) {
                              final f = folders[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SoftTap(
                                  onTap: () => Navigator.of(context).pop(f),
                                  label: pth.basename(f),
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    decoration: raisedDeco(p, radius: 18),
                                    child: Row(
                                      children: [
                                        Icon(Icons.folder_outlined,
                                            size: 20, color: p.accent),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(pth.basename(f),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: ts(context, 15)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final clean = AppController.cleanFolderName(_ctrl.text);
    if (clean == null) return;
    Navigator.of(context).pop(clean);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: p.ring),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New folder', style: ts(context, 22)),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: ts(context, 16),
              cursorColor: p.accent,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Folder name',
                hintStyle: ts(context, 16, color: p.muted),
                filled: true,
                fillColor: p.pressed,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: p.ring),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: p.ring),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: p.accent),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SoftPill(label: 'Create', onTap: _submit),
            const SizedBox(height: 12),
            SoftPill(
              label: 'Cancel',
              color: p.muted,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
