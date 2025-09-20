import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_controller.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool showSignIn = true;
  SignUpPrefillData? _pendingPrefill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final error = authState.errorMessage;
    final isLoading = authState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Coalition for Montana',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                showSignIn
                    ? 'Welcome back! Sign in to continue building the coalition.'
                    : 'Create your account to connect with candidates and events tailored to your priorities.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showSignIn ? 'Sign in' : 'Create an account',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (showSignIn)
                        _SignInForm(
                          onToggle: _toggleForm,
                          onGoogleSignIn: _handleGoogleSignIn,
                          isLoading: isLoading,
                        )
                      else
                        _SignUpForm(
                          onToggle: _toggleForm,
                          onGoogleSignIn: _handleGoogleSignIn,
                          isLoading: isLoading,
                          prefill: _pendingPrefill,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleForm() {
    setState(() {
      showSignIn = !showSignIn;
      _pendingPrefill = null;
    });
  }

  Future<void> _handleGoogleSignIn() async {
    FocusScope.of(context).unfocus();
    final result = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;

    switch (result.status) {
      case GoogleSignInStatus.signedIn:
      case GoogleSignInStatus.cancelled:
        return;
      case GoogleSignInStatus.failure:
        if (result.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message!)),
          );
        }
        return;
      case GoogleSignInStatus.needsRegistration:
        final email = result.email;
        if (email == null) return;
        setState(() {
          showSignIn = false;
          _pendingPrefill = SignUpPrefillData(
            email: email,
            firstName: result.firstName,
            lastName: result.lastName,
            viaGoogle: true,
          );
        });
    }
  }
}

class SignUpPrefillData {
  const SignUpPrefillData({
    required this.email,
    this.firstName,
    this.lastName,
    this.viaGoogle = false,
  });

  final String email;
  final String? firstName;
  final String? lastName;
  final bool viaGoogle;
}

class _SignUpForm extends ConsumerStatefulWidget {
  const _SignUpForm({
    required this.onToggle,
    required this.onGoogleSignIn,
    required this.isLoading,
    this.prefill,
  });

  final VoidCallback onToggle;
  final Future<void> Function() onGoogleSignIn;
  final bool isLoading;
  final SignUpPrefillData? prefill;

  @override
  ConsumerState<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends ConsumerState<_SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _zipController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isGoogleUser = false;

  @override
  void initState() {
    super.initState();
    _applyPrefill(widget.prefill);
  }

  @override
  void didUpdateWidget(covariant _SignUpForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefill != oldWidget.prefill) {
      _applyPrefill(widget.prefill);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _zipController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Username'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              if (value.trim().length < 3) {
                return 'At least 3 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email address'),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _zipController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'ZIP code'),
            validator: (value) =>
                value == null || value.trim().length < 5 ? 'Enter a valid ZIP' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              if (value.length < 8) return 'At least 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              if (value != _passwordController.text) return 'Passwords must match';
              return null;
            },
          ),
          if (widget.prefill?.viaGoogle ?? false) ...[
            const SizedBox(height: 16),
            Text(
              'Finish your profile to link your Google account.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.isLoading ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _SubmitLabel(
                label: 'Create account',
                isLoading: widget.isLoading,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.isLoading ? null : () => widget.onGoogleSignIn(),
            icon: const Icon(Icons.login),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.isLoading ? null : widget.onToggle,
            child: const Text('Already have an account? Sign in'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).register(
          AuthCredentials(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            zipCode: _zipController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            confirmPassword: _confirmPasswordController.text,
            isGoogleUser: _isGoogleUser,
          ),
        );
  }

  void _applyPrefill(SignUpPrefillData? prefill) {
    if (prefill == null) {
      _isGoogleUser = false;
      return;
    }
    _isGoogleUser = prefill.viaGoogle;
    _emailController.text = prefill.email;
    if (prefill.firstName != null) {
      _firstNameController.text = prefill.firstName!;
    }
    if (prefill.lastName != null) {
      _lastNameController.text = prefill.lastName!;
    }
  }
}

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm({
    required this.onToggle,
    required this.onGoogleSignIn,
    required this.isLoading,
  });

  final VoidCallback onToggle;
  final Future<void> Function() onGoogleSignIn;
  final bool isLoading;

  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _identifierController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email or username'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.isLoading ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _SubmitLabel(
                label: 'Sign in',
                isLoading: widget.isLoading,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.isLoading ? null : () => widget.onGoogleSignIn(),
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.isLoading ? null : widget.onToggle,
            child: const Text('Need an account? Register'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signIn(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );
  }
}

class _SubmitLabel extends StatelessWidget {
  const _SubmitLabel({required this.label, required this.isLoading});

  final String label;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return Text(label);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
