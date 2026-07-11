import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../models/annonce.dart';
import '../services/annonce_service.dart';
import '../widgets/shared_widgets.dart';

String _heure(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : DateFormat('dd/MM HH:mm').format(d);
}

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _service = AnnonceService();
  List<Conversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final c = await _service.getConversations();
    if (mounted) setState(() { _conversations = c; _loading = false; });
  }

  Future<void> _ouvrir(Conversation c) async {
    await Navigator.push(context, slideRoute(ConversationScreen(conversationId: c.id)));
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.adMessages, style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _conversations.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.forum_outlined, size: 56, color: context.cHint),
                      const SizedBox(height: 12),
                      Center(child: Text(t.adNoMessages, style: TextStyle(color: context.cTextSub))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _conversations.length,
                      itemBuilder: (_, i) => _ConversationCard(
                        conv: _conversations[i], onTap: () => _ouvrir(_conversations[i])),
                    ),
            ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;
  const _ConversationCard({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cBorder),
        ),
        child: Row(children: [
          CircleAvatar2(
            initiales: (conv.chercheurNom.isNotEmpty ? conv.chercheurNom[0] : '?').toUpperCase(),
            bg: context.cBlue3, fg: AppColors.blue, size: 42),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(conv.chercheurNom,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.cText))),
              Text(_heure(conv.dateDernierMessage),
                  style: TextStyle(fontSize: 11, color: context.cHint)),
            ]),
            const SizedBox(height: 2),
            Text(conv.annonceTitre, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(conv.dernierMessage,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.cTextSub))),
              if (conv.nonLus > 0) Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.all(Radius.circular(10))),
                child: Text('${conv.nonLus}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ─────────────────────────────── Fil de conversation ─────────────────────────
class ConversationScreen extends StatefulWidget {
  final int conversationId;
  const ConversationScreen({required this.conversationId, super.key});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _service = AnnonceService();
  final _corps = TextEditingController();
  final _scroll = ScrollController();
  Conversation? _conv;
  bool _loading = true, _envoi = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _corps.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final c = await _service.getConversation(widget.conversationId);
    if (mounted) setState(() { _conv = c; _loading = false; });
    _versLeBas();
  }

  void _versLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _envoyer() async {
    final txt = _corps.text.trim();
    if (txt.isEmpty) return;
    setState(() => _envoi = true);
    final maj = await _service.repondreConversation(widget.conversationId, txt);
    if (!mounted) return;
    setState(() {
      _envoi = false;
      if (maj != null) { _conv = maj; _corps.clear(); }
    });
    _versLeBas();
  }

  Future<void> _action(String action) async {
    final ok = action == 'bloquer'
        ? await _service.bloquerConversation(widget.conversationId)
        : await _service.archiverConversation(widget.conversationId);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final conv = _conv;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(conv?.chercheurNom ?? '…',
            style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          if (conv != null) PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: context.cText),
            color: context.cCard,
            onSelected: _action,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archiver', child: Text(t.adArchive, style: TextStyle(color: context.cText))),
              PopupMenuItem(value: 'bloquer', child: Text(t.adBlock, style: const TextStyle(color: AppColors.danger))),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : conv == null
              ? Center(child: Text(t.adNoMessages, style: TextStyle(color: context.cTextSub)))
              : Column(children: [
                  Expanded(child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: conv.messages.length,
                    itemBuilder: (_, i) => _Bulle(msg: conv.messages[i]),
                  )),
                  if (conv.estOuverte)
                    _barreEnvoi(t)
                  else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t.adConversationClosed,
                          textAlign: TextAlign.center, style: TextStyle(color: context.cHint, fontSize: 13)),
                    ),
                ]),
    );
  }

  Widget _barreEnvoi(AppLocalizations t) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _corps,
              minLines: 1, maxLines: 4,
              style: TextStyle(color: context.cText),
              decoration: InputDecoration(
                hintText: t.adYourReply,
                filled: true, fillColor: context.cCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _envoi ? null : _envoyer,
              child: Container(
                width: 46, height: 46,
                decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                child: _envoi
                    ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      );
}

class _Bulle extends StatelessWidget {
  final Message msg;
  const _Bulle({required this.msg});

  @override
  Widget build(BuildContext context) {
    final moi = msg.estMoi;
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: moi ? AppColors.blue : context.cCard,
          borderRadius: BorderRadius.circular(14),
          border: moi ? null : Border.all(color: context.cBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.corps, style: TextStyle(color: moi ? Colors.white : context.cText, fontSize: 14)),
          const SizedBox(height: 3),
          Text(_heure(msg.dateEnvoi),
              style: TextStyle(color: moi ? Colors.white70 : context.cHint, fontSize: 10)),
        ]),
      ),
    );
  }
}
