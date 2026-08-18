import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session_controller.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

enum AuthView { phone, email, register, forgot }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthView view = AuthView.phone;

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: AppSystemUi.light,
    child: Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -90,
            child: Container(
              width: 270,
              height: 270,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x55D97757), Color(0x0010172A)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const MotionEntrance(
                  delay: Duration(milliseconds: 120),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 18),
                    child: BrandMark(dark: true, height: 44),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(36),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
                        switchOutCurve: const Cubic(0.3, 0, 1, 1),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                          child: SlideTransition(
                            position:
                                Tween(
                                  begin: const Offset(.055, .012),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: const Cubic(0.05, 0.7, 0.1, 1),
                                  ),
                                ),
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: .985,
                                end: 1,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                        ),
                        child: switch (view) {
                          AuthView.phone => PhoneLogin(
                            key: const ValueKey('phone'),
                            api: widget.api,
                            session: widget.session,
                            change: _change,
                          ),
                          AuthView.email => EmailLogin(
                            key: const ValueKey('email'),
                            api: widget.api,
                            session: widget.session,
                            change: _change,
                          ),
                          AuthView.register => RegisterForm(
                            key: const ValueKey('register'),
                            api: widget.api,
                            session: widget.session,
                            change: _change,
                          ),
                          AuthView.forgot => ForgotPassword(
                            key: const ValueKey('forgot'),
                            api: widget.api,
                            change: _change,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _change(AuthView next) => setState(() => view = next);
}

class PhoneLogin extends StatefulWidget {
  const PhoneLogin({
    super.key,
    required this.api,
    required this.session,
    required this.change,
  });
  final ApiClient api;
  final SessionController session;
  final ValueChanged<AuthView> change;

  @override
  State<PhoneLogin> createState() => _PhoneLoginState();
}

class _PhoneLoginState extends State<PhoneLogin> {
  final phone = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AuthHeading(
        title: 'Welcome back',
        subtitle:
            'Enter your Egyptian mobile number to receive a secure access code.',
      ),
      const SizedBox(height: 26),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        decoration: const InputDecoration(
          labelText: 'Mobile number',
          prefixText: '+20  ',
          hintText: '10 1234 5678',
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: busy ? null : _send,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_rounded),
        label: const Text('Send verification code'),
      ),
      const SizedBox(height: 26),
      const OrDivider(),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () => widget.change(AuthView.email),
        icon: const Icon(Icons.mail_outline_rounded),
        label: const Text('Continue with email'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => widget.change(AuthView.register),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Create an account'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
        ),
      ),
    ],
  );

  Future<void> _send() async {
    if (phone.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.api.post(
        '/mobile/auth/buyer/otp/request',
        data: {'phone': phone.text.trim()},
      );
      if (!mounted) return;
      final response = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone.text.trim(),
            title: 'Verify your phone',
            subtitle: 'We sent a 6-digit access code to your number.',
            onVerify: (code) => widget.api.post(
              '/mobile/auth/buyer/otp/verify',
              data: {'phone': phone.text.trim(), 'code': code},
            ),
            onResend: () => widget.api.post(
              '/mobile/auth/buyer/otp/request',
              data: {'phone': phone.text.trim()},
            ),
          ),
        ),
      );
      if (response == null || !mounted) return;

      Map<String, dynamic>? sessionResponse = response;
      if (response['requires_registration'] == true) {
        sessionResponse = await Navigator.of(context)
            .push<Map<String, dynamic>>(
              MaterialPageRoute(
                builder: (_) => CompletePhoneSignupScreen(
                  api: widget.api,
                  phone: phone.text.trim(),
                  registrationToken: response['registration_token'].toString(),
                ),
              ),
            );
      }
      if (sessionResponse != null) {
        await widget.session.acceptBuyerSession(sessionResponse);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class EmailLogin extends StatefulWidget {
  const EmailLogin({
    super.key,
    required this.api,
    required this.session,
    required this.change,
  });
  final ApiClient api;
  final SessionController session;
  final ValueChanged<AuthView> change;

  @override
  State<EmailLogin> createState() => _EmailLoginState();
}

class _EmailLoginState extends State<EmailLogin> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  bool busy = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AuthBack(onTap: () => widget.change(AuthView.phone)),
      const AuthHeading(
        title: 'Sign in with email',
        subtitle: 'Use the email and password connected to your buyer account.',
      ),
      const SizedBox(height: 24),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: password,
        obscureText: hidden,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(
            onPressed: () => setState(() => hidden = !hidden),
            icon: Icon(
              hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => widget.change(AuthView.forgot),
          child: const Text('Forgot password?'),
        ),
      ),
      FilledButton(
        onPressed: busy ? null : _login,
        child: busy
            ? const CircularProgressIndicator(strokeWidth: 2)
            : const Text('Sign in'),
      ),
      const SizedBox(height: 18),
      Center(
        child: TextButton(
          onPressed: () => widget.change(AuthView.register),
          child: const Text('New here? Create an account'),
        ),
      ),
    ],
  );

  Future<void> _login() async {
    setState(() => busy = true);
    try {
      final response = await widget.api.post(
        '/mobile/auth/buyer/password',
        data: {'email': email.text.trim(), 'password': password.text},
      );
      await widget.session.acceptBuyerSession(response);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class RegisterForm extends StatefulWidget {
  const RegisterForm({
    super.key,
    required this.api,
    required this.session,
    required this.change,
  });
  final ApiClient api;
  final SessionController session;
  final ValueChanged<AuthView> change;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  bool accepted = false;
  bool busy = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AuthBack(onTap: () => widget.change(AuthView.phone)),
      const AuthHeading(
        title: 'Create your account',
        subtitle:
            'Your account is created only after your phone code is verified.',
      ),
      const SizedBox(height: 22),
      TextField(
        controller: name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Mobile number',
          prefixText: '+20  ',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: password,
        obscureText: hidden,
        decoration: InputDecoration(
          labelText: 'Strong password',
          helperText: 'Uppercase, lowercase, number and symbol',
          suffixIcon: IconButton(
            onPressed: () => setState(() => hidden = !hidden),
            icon: Icon(
              hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      CheckboxListTile(
        value: accepted,
        onChanged: (value) => setState(() => accepted = value ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'I agree to the Terms and Privacy Policy',
          style: TextStyle(fontSize: 13),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: !accepted || busy ? null : _register,
        child: busy
            ? const CircularProgressIndicator(strokeWidth: 2)
            : const Text('Send code & continue'),
      ),
      const SizedBox(height: 18),
      Center(
        child: TextButton(
          onPressed: () => widget.change(AuthView.email),
          child: const Text('Already registered? Sign in'),
        ),
      ),
    ],
  );

  Future<void> _register() async {
    setState(() => busy = true);
    try {
      final requested = await widget.api.post(
        '/mobile/auth/buyer/register/request',
        data: {
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
        },
      );
      if (!mounted) return;
      final response = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone.text.trim(),
            title: 'Finish your sign up',
            subtitle:
                'Enter the code to verify your phone and create the account.',
            onVerify: (code) => widget.api.post(
              '/mobile/auth/buyer/register/complete',
              data: {
                'registration_token': requested['registration_token'],
                'phone': phone.text.trim(),
                'code': code,
              },
            ),
            onResend: () async {
              final next = await widget.api.post(
                '/mobile/auth/buyer/register/request',
                data: {
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'password': password.text,
                },
              );
              requested.addAll(next);
              return next;
            },
          ),
        ),
      );
      if (response != null) await widget.session.acceptBuyerSession(response);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, required this.api, required this.change});
  final ApiClient api;
  final ValueChanged<AuthView> change;

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final phone = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AuthBack(onTap: () => widget.change(AuthView.email)),
      const AuthHeading(
        title: 'Reset password',
        subtitle:
            'We will verify your registered phone before allowing a new password.',
      ),
      const SizedBox(height: 24),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Mobile number',
          prefixText: '+20  ',
        ),
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: busy ? null : _send,
        child: busy
            ? const CircularProgressIndicator(strokeWidth: 2)
            : const Text('Send reset code'),
      ),
    ],
  );

  Future<void> _send() async {
    setState(() => busy = true);
    try {
      await widget.api.post(
        '/mobile/auth/buyer/password/reset/request',
        data: {'phone': phone.text.trim()},
      );
      if (!mounted) return;
      final verified = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone.text.trim(),
            title: 'Verify reset code',
            subtitle: 'Enter the 6-digit code sent to your phone.',
            onVerify: (code) => widget.api.post(
              '/mobile/auth/buyer/password/reset/verify',
              data: {'phone': phone.text.trim(), 'code': code},
            ),
            onResend: () => widget.api.post(
              '/mobile/auth/buyer/password/reset/request',
              data: {'phone': phone.text.trim()},
            ),
          ),
        ),
      );
      if (verified == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NewPasswordScreen(
            api: widget.api,
            resetToken: verified['reset_token'].toString(),
          ),
        ),
      );
      if (mounted) widget.change(AuthView.email);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.title,
    required this.subtitle,
    required this.onVerify,
    this.onResend,
    this.showResend = true,
    this.maskPhone = true,
  });
  final String phone;
  final String title;
  final String subtitle;
  final Future<Map<String, dynamic>> Function(String code) onVerify;
  final Future<Map<String, dynamic>> Function()? onResend;
  final bool showResend;
  final bool maskPhone;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  final controllers = List.generate(6, (_) => TextEditingController());
  final nodes = List.generate(6, (_) => FocusNode());
  late final AnimationController shakeController;
  late final Animation<double> shakeAnimation;
  Timer? timer;
  int seconds = 60;
  bool busy = false;
  bool verified = false;
  String? error;
  String? lastSubmittedCode;

  @override
  void initState() {
    super.initState();
    shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -10, end: 9), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 9, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: shakeController, curve: Curves.easeInOut),
        );
    for (final node in nodes) {
      node.addListener(_focusChanged);
    }
    _startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    shakeController.dispose();
    for (final controller in controllers) {
      controller.dispose();
    }
    for (final node in nodes) {
      node.removeListener(_focusChanged);
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: AppSystemUi.dark,
    child: Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const BrandMark(),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              Text(
                widget.phone.isEmpty
                    ? widget.subtitle
                    : '${widget.subtitle}\n${widget.maskPhone ? _masked(widget.phone) : widget.phone}',
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 30),
              _buildOtpFields(context),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(sizeFactor: animation, child: child),
                ),
                child: error == null
                    ? const SizedBox.shrink(key: ValueKey('otp-no-error'))
                    : Padding(
                        key: ValueKey(error),
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              if (widget.showResend) ...[
                Center(
                  child: Text(
                    seconds > 0
                        ? 'Resend available in 00:${seconds.toString().padLeft(2, '0')}'
                        : 'Didn\'t receive the code?',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: seconds > 0 || busy ? null : _resend,
                    child: const Text('Resend code'),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: busy || verified ? null : _verify,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: verified
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('verified'),
                        )
                      : busy
                      ? const SizedBox.square(
                          key: ValueKey('checking'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.verified_user_rounded,
                          key: ValueKey('verify'),
                        ),
                ),
                label: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    verified
                        ? 'Verified'
                        : busy
                        ? 'Checking code...'
                        : 'Verify & continue',
                    key: ValueKey('$busy-$verified'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '🔒  SECURE VERIFICATION',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildOtpFields(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: shakeAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(reduceMotion ? 0 : shakeAnimation.value, 0),
        child: child,
      ),
      child: Row(
        children: List.generate(6, (index) {
          final filled = controllers[index].text.isNotEmpty;
          final focused = nodes[index].hasFocus;
          final background = verified
              ? const Color(0xFFDDF5E8)
              : error != null
              ? const Color(0xFFFFE4E0)
              : filled
              ? AppColors.yellow.withValues(alpha: 0.34)
              : const Color(0xFFE9E5E1);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                transform: Matrix4.diagonal3Values(
                  filled ? 1.0 : 0.97,
                  filled ? 1.0 : 0.97,
                  1,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: error != null
                        ? const Color(0xFFEF5350)
                        : focused
                        ? AppColors.coral
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: controllers[index],
                  focusNode: nodes[index],
                  readOnly: busy || verified,
                  keyboardType: TextInputType.number,
                  textInputAction: index == 5
                      ? TextInputAction.done
                      : TextInputAction.next,
                  autofillHints: index == 0
                      ? const [AutofillHints.oneTimeCode]
                      : null,
                  enableSuggestions: false,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    errorText: null,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                  ),
                  onChanged: (value) => _digitChanged(index, value),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _digitChanged(int index, String value) {
    final digit = value
        .replaceAll(RegExp(r'\D'), '')
        .characters
        .take(1)
        .toString();
    if (controllers[index].text != digit) {
      controllers[index].value = TextEditingValue(
        text: digit,
        selection: TextSelection.collapsed(offset: digit.length),
      );
    }

    setState(() {
      error = null;
      lastSubmittedCode = null;
    });

    if (digit.isNotEmpty && index < 5) {
      nodes[index + 1].requestFocus();
    } else if (digit.isEmpty && index > 0) {
      nodes[index - 1].requestFocus();
    }

    final code = controllers.map((controller) => controller.text).join();
    if (code.length == 6 && !busy && !verified) {
      FocusScope.of(context).unfocus();
      unawaited(_verify());
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _showOtpError(String message) {
    if (!mounted) return;
    setState(() {
      busy = false;
      error = message;
      lastSubmittedCode = null;
    });
    if (!MediaQuery.disableAnimationsOf(context)) {
      shakeController.forward(from: 0);
    }
  }

  Future<void> _verify() async {
    if (busy || verified) return;
    final code = controllers.map((c) => c.text).join();
    if (code.length != 6) {
      _showOtpError('Enter all 6 digits.');
      return;
    }
    if (lastSubmittedCode == code) return;
    lastSubmittedCode = code;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await widget.onVerify(code);
      if (!mounted) return;
      setState(() {
        busy = false;
        verified = true;
      });
      if (!MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      if (mounted) Navigator.pop(context, response);
    } catch (value) {
      _showOtpError(
        value is ApiException ? value.message : 'Invalid OTP code.',
      );
    }
  }

  Future<void> _resend() async {
    setState(() {
      busy = true;
      verified = false;
      error = null;
      lastSubmittedCode = null;
    });
    try {
      await widget.onResend?.call();
      for (final controller in controllers) {
        controller.clear();
      }
      nodes.first.requestFocus();
      _startTimer();
    } catch (value) {
      if (mounted) {
        setState(
          () => error = value is ApiException
              ? value.message
              : 'Could not resend the code.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _startTimer() {
    timer?.cancel();
    if (!widget.showResend) {
      seconds = 0;
      return;
    }
    setState(() => seconds = 60);
    timer = Timer.periodic(const Duration(seconds: 1), (value) {
      if (!mounted) return;
      if (seconds <= 1) {
        value.cancel();
        setState(() => seconds = 0);
      } else {
        setState(() => seconds--);
      }
    });
  }

  String _masked(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return input;
    return '+20 ••• ••• ${digits.substring(digits.length - 4)}';
  }
}

class CompletePhoneSignupScreen extends StatefulWidget {
  const CompletePhoneSignupScreen({
    super.key,
    required this.api,
    required this.phone,
    required this.registrationToken,
  });

  final ApiClient api;
  final String phone;
  final String registrationToken;

  @override
  State<CompletePhoneSignupScreen> createState() =>
      _CompletePhoneSignupScreenState();
}

class _CompletePhoneSignupScreenState extends State<CompletePhoneSignupScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool hidden = true;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: AppSystemUi.dark,
    child: Scaffold(
      appBar: AppBar(title: const BrandMark(), centerTitle: true),
      body: SafeArea(
        top: false,
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
            children: [
              const AuthHeading(
                title: 'Create your account',
                subtitle:
                    'Your phone is verified. Add your details to finish signing up and continue.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE6DC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_maskedPhone(widget.phone)} verified',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter your full name.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: password,
                obscureText: hidden,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Uppercase, lowercase, number and symbol',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
                validator: (value) {
                  final text = value ?? '';
                  final strong = RegExp(
                    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$',
                  ).hasMatch(text);
                  return strong ? null : 'Use a stronger password.';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: confirmation,
                obscureText: hidden,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (value) =>
                    value != password.text ? 'Passwords do not match.' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : _submit,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Create account & continue'),
              ),
              const SizedBox(height: 14),
              const Text(
                'You cannot continue to tickets or purchases until these account details are completed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    setState(() => busy = true);
    try {
      final response = await widget.api.post(
        '/mobile/auth/buyer/otp/registration',
        data: {
          'registration_token': widget.registrationToken,
          'name': name.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          'password_confirmation': confirmation.text,
        },
      );
      if (mounted) Navigator.pop(context, response);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _maskedPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return input;
    return '+20 ••• ••• ${digits.substring(digits.length - 4)}';
  }
}

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({
    super.key,
    required this.api,
    required this.resetToken,
  });
  final ApiClient api;
  final String resetToken;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New password')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthHeading(
            title: 'Choose a new password',
            subtitle: 'Use uppercase, lowercase, a number and a symbol.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmation,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm password'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : _save,
            child: busy
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Text('Save password'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await widget.api.post(
        '/mobile/auth/buyer/password/reset',
        data: {
          'reset_token': widget.resetToken,
          'password': password.text,
          'password_confirmation': confirmation.text,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.muted, height: 1.5),
      ),
    ],
  );
}

class AuthBack extends StatelessWidget {
  const AuthBack({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: IconButton.filledTonal(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_back_rounded),
    ),
  );
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          'OR',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: AppColors.muted,
          ),
        ),
      ),
      Expanded(child: Divider()),
    ],
  );
}
