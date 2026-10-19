import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../routes/app_routes.dart';
import 'auth_controller.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _required(String? v, String label) =>
    (v == null || v.trim().isEmpty) ? '$label is required' : null;

String? _validateEmail(String? v) {
  final missing = _required(v, 'Email');
  if (missing != null) return missing;
  return _emailPattern.hasMatch(v!.trim()) ? null : 'Enter a valid email';
}

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Password is required';
  if (v.length < 8) return 'Use at least 8 characters';
  return null;
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text('SmartStock AI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError(this.controller);

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final message = controller.formError.value;
      if (message == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Container(
        key: const Key('auth-form-error'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      );
    });
  }
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _org = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  AuthController get _c => Get.find<AuthController>();

  @override
  void dispose() {
    _org.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _c.login(
      organization: _org.text,
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Sign in to your organisation',
      children: [
        _FormError(_c),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('login-org'),
                  controller: _org,
                  decoration: const InputDecoration(
                    labelText: 'Organisation',
                    hintText: 'organisation-slug',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => _required(v, 'Organisation'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login-email'),
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
                const SizedBox(height: 20),
                Obx(() => FilledButton(
                      key: const Key('login-submit'),
                      onPressed: _c.submitting.value ? null : _submit,
                      child: _c.submitting.value
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            _c.formError.value = null;
            Get.toNamed(Routes.register);
          },
          child: const Text('Create a new organisation'),
        ),
      ],
    );
  }
}

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _orgName = TextEditingController();
  final _orgSlug = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  AuthController get _c => Get.find<AuthController>();

  @override
  void dispose() {
    for (final c in [_orgName, _orgSlug, _fullName, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _c.register(
      organizationName: _orgName.text,
      organizationSlug: _orgSlug.text,
      fullName: _fullName.text,
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create an organisation',
      children: [
        _FormError(_c),
        Form(
          key: _formKey,
          child: Obx(() {
            final serverErrors = _c.fieldErrors;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('register-org-name'),
                  controller: _orgName,
                  decoration: InputDecoration(
                    labelText: 'Organisation name',
                    errorText: serverErrors['organization_name'],
                  ),
                  validator: (v) {
                    final missing = _required(v, 'Organisation name');
                    if (missing != null) return missing;
                    return v!.trim().length < 2 ? 'Use at least 2 characters' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-org-slug'),
                  controller: _orgSlug,
                  decoration: InputDecoration(
                    labelText: 'Organisation slug (optional)',
                    helperText: 'Used to sign in. Generated from the name if blank.',
                    errorText: serverErrors['organization_slug'],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-full-name'),
                  controller: _fullName,
                  decoration: InputDecoration(
                    labelText: 'Your name (optional)',
                    errorText: serverErrors['full_name'],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: serverErrors['email'],
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-password'),
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    errorText: serverErrors['password'],
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('register-submit'),
                  onPressed: _c.submitting.value ? null : _submit,
                  child: _c.submitting.value
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create organisation'),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Get.back<void>(),
          child: const Text('I already have an account'),
        ),
      ],
    );
  }
}
