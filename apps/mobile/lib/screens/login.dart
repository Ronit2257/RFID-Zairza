import 'package:flutter/material.dart';

import '../core/store.dart';

class LoginScreen extends StatefulWidget {
  final ClubStore store;
  const LoginScreen({super.key, required this.store});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final server = TextEditingController(
    text: const String.fromEnvironment('API_BASE_URL', defaultValue: ''),
  );
  final code = TextEditingController();
  bool visible = false;
  @override
  void dispose() {
    server.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.blur_on_rounded,
                  size: 58,
                  color: Color(0xff173f35),
                ),
                const SizedBox(height: 24),
                const Text(
                  'ZAIRZA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'A little closer\nto the club.',
                  style: TextStyle(
                    fontSize: 38,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'See who’s in, catch up on activity, and keep your club connected.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Club server URL',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: code,
                  obscureText: !visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: 'Your leadership access code',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      tooltip: visible ? 'Hide code' : 'Show code',
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (widget.store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      widget.store.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: widget.store.busy ? null : submit,
                    child: widget.store.busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Enter the club',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 22),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'For approved club leadership. Ask your operator for a personal access code.',
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  void submit() {
    if (code.text.trim().isNotEmpty && !widget.store.busy) {
      widget.store.login(server.text, code.text);
    }
  }
}
