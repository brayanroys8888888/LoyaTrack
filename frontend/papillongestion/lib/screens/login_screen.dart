import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../main_shell.dart';
import '../services/auth_service.dart';
import 'forgot_password_screen.dart';
import 'otp_login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email   = TextEditingController();
  final _pass    = TextEditingController();
  bool _obscure  = true;
  bool _remember = true;
  bool _loading  = false;

  @override
  void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  void _login() async {
    final identifiant = _email.text.trim();
    final pass = _pass.text;

    if (identifiant.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).fillAllFields), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _loading = true);
    final res = await AuthService().login(identifiant, pass);
    if (!mounted) return;
    setState(() => _loading = false);

    if (res.success) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
    } else if (res.otpRequired) {
      Navigator.of(context).push(slideRoute(
        OtpLoginScreen(userId: res.userId!, devCode: res.devCode),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? AppLocalizations.of(context).invalidCredentials), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: dark ? AppColors.bgDark : Colors.white,
      // L'écran entier défile : quand le clavier apparaît, l'en-tête remonte
      // au lieu de bloquer les champs (plus de bande bleue fixe qui gêne).
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const _AuthBrand(),
                const SizedBox(height: 28),
                Text(t.loginTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: context.cText)),
                const SizedBox(height: 6),
                Text(t.loginWelcome,
                    style: TextStyle(fontSize: 14, color: context.cTextSub)),
                const SizedBox(height: 28),
                  _Label(t.phoneOrEmail, context),
                  const SizedBox(height: 8),
                  _Field(ctrl: _email, hint: t.phoneOrEmail,
                      icon: Icons.person_outline_rounded,
                      type: TextInputType.text,
                      context: context),
                  const SizedBox(height: 16),
                  _Label(t.password, context),
                  const SizedBox(height: 8),
                  _Field(
                      ctrl: _pass,
                      hint: t.passwordHint,
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscure,
                      context: context,
                      suffix: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: context.cHint),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      )),
                  const SizedBox(height: 12),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          _Checkbox(value: _remember,
                              onTap: () =>
                                  setState(() => _remember = !_remember)),
                          const SizedBox(width: 8),
                          Text(t.rememberMe,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: context.cTextSub)),
                        ]),
                        GestureDetector(
                          onTap: () => Navigator.push(context, slideRoute(const ForgotPasswordScreen())),
                          child: Text(t.forgotPassword,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.blue,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                  const SizedBox(height: 24),
                  _GradientBtn(
                      label: t.signIn,
                      loading: _loading,
                      onTap: _login),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Divider(color: context.cBorder)),
                    Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(t.orContinueWith,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.cHint))),
                    Expanded(child: Divider(color: context.cBorder)),
                  ]),
                  const SizedBox(height: 16),
                  _GoogleBtn(context: context),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        slideRoute(const RegisterScreen())
                      );
                    },
                    child: Center(
                      child: RichText(
                        text: TextSpan(
                          text: t.noAccountYet,
                          style: TextStyle(color: context.cTextSub, fontSize: 13),
                          children: [
                            TextSpan(
                                text: t.createAccount,
                                style: const TextStyle(
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.w700))
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nom    = TextEditingController();
  final _email  = TextEditingController();
  final _tel    = TextEditingController();
  final _pass   = TextEditingController();
  final _conf   = TextEditingController();
  bool _obscure = true;
  bool _terms   = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_nom, _email, _tel, _pass, _conf]) c.dispose();
    super.dispose();
  }

  void _register() async {
    final t = AppLocalizations.of(context);
    final nom = _nom.text.trim();
    final email = _email.text.trim();
    final tel = _tel.text.trim();
    final pass = _pass.text;
    final conf = _conf.text;

    if (nom.isEmpty || pass.isEmpty || conf.isEmpty || (email.isEmpty && tel.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.registerRequired), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (pass != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.passwordsDontMatch), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (!_terms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.mustAcceptTerms), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _loading = true);
    
    final parts = nom.split(' ');
    final prenom = parts.isNotEmpty ? parts.first : '';
    final nomFamille = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final res = await AuthService().register(
      email: email, telephone: tel, password: pass, confirmPassword: conf,
      nom: nomFamille, prenom: prenom,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res.success) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? t.registerError), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: dark ? AppColors.bgDark : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              color: context.cSurface,
                              borderRadius: BorderRadius.circular(11)),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: context.cText, size: 15)),
                    ),
                    const _AuthBrand(compact: true),
                  ],
                ),
                const SizedBox(height: 24),
                Text(t.createAccount,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: context.cText)),
                const SizedBox(height: 6),
                Text(t.registerSubtitle,
                    style: TextStyle(fontSize: 14, color: context.cTextSub)),
                const SizedBox(height: 24),
                  _Label(t.fullName, context),
                  const SizedBox(height: 8),
                  _Field(ctrl: _nom, hint: 'Jean Dupont',
                      icon: Icons.person_outline_rounded,
                      context: context),
                  const SizedBox(height: 14),
                  _Label(t.emailAddress, context),
                  const SizedBox(height: 8),
                  _Field(ctrl: _email, hint: 'jean@email.com',
                      icon: Icons.email_outlined,
                      type: TextInputType.emailAddress,
                      context: context),
                  const SizedBox(height: 14),
                  _Label(t.phone, context),
                  const SizedBox(height: 8),
                  _Field(ctrl: _tel, hint: '+237 6 _ _ _',
                      icon: Icons.phone_outlined,
                      type: TextInputType.phone,
                      context: context),
                  const SizedBox(height: 14),
                  _Label(t.password, context),
                  const SizedBox(height: 8),
                  _Field(
                      ctrl: _pass,
                      hint: t.passwordMin8,
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscure,
                      context: context,
                      suffix: IconButton(
                          icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: context.cHint),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure))),
                  const SizedBox(height: 14),
                  _Label(t.confirmPassword, context),
                  const SizedBox(height: 8),
                  _Field(ctrl: _conf, hint: t.repeatPassword,
                      icon: Icons.lock_outline_rounded,
                      obscure: true,
                      context: context),
                  const SizedBox(height: 16),
                  // CGU
                  GestureDetector(
                    onTap: () => setState(() => _terms = !_terms),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Checkbox(
                              value: _terms,
                              onTap: () =>
                                  setState(() => _terms = !_terms)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                  text: t.acceptThe,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.cTextSub),
                                  children: [
                                    TextSpan(
                                        text: t.termsOfUse,
                                        style: const TextStyle(
                                            color: AppColors.blue,
                                            fontWeight:
                                                FontWeight.w600)),
                                    TextSpan(text: t.andThe),
                                    TextSpan(
                                        text: t.privacyPolicy,
                                        style: const TextStyle(
                                            color: AppColors.blue,
                                            fontWeight:
                                                FontWeight.w600)),
                                  ]),
                            ),
                          ),
                        ]),
                  ),
                  const SizedBox(height: 24),
                  _GradientBtn(
                      label: t.createMyAccount,
                      loading: _loading,
                      onTap: _register),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                            text: t.alreadyHaveAccount,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.cTextSub),
                            children: [
                              TextSpan(
                                  text: t.signIn,
                                  style: const TextStyle(
                                      color: AppColors.blue,
                                      fontWeight: FontWeight.w700))
                            ]),
                      ),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ─── Widgets helpers ──────────────────────────────────────────────────────────

/// Marque LoyaTrack : badge dégradé avec le logo + le nom. `compact` réduit la
/// taille (utilisé dans la barre supérieure de l'inscription).
class _AuthBrand extends StatelessWidget {
  final bool compact;
  const _AuthBrand({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = compact ? 38.0 : 48.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: s,
        height: s,
        padding: EdgeInsets.all(compact ? 7 : 9),
        decoration: BoxDecoration(
          gradient: kGradient,
          borderRadius: BorderRadius.circular(compact ? 11 : 14),
          boxShadow: [
            BoxShadow(
                color: AppColors.blue.withOpacity(0.30),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Image.asset('assets/images/logo/loyatrack_logo.png',
            fit: BoxFit.contain),
      ),
      const SizedBox(width: 10),
      Text('LoyaTrack',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 16 : 20,
              color: context.cText,
              letterSpacing: -0.5)),
    ]);
  }
}

Widget _Label(String text, BuildContext context) => Text(
      text.toUpperCase(),
      style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: context.cTextSub,
          letterSpacing: 0.8),
    );

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? type;
  final Widget? suffix;
  final BuildContext context;
  const _Field(
      {required this.ctrl,
      required this.hint,
      required this.icon,
      required this.context,
      this.obscure = false,
      this.type,
      this.suffix});

  @override
  Widget build(BuildContext ctx) => TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        style: TextStyle(fontSize: 14, color: context.cText),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: context.cHint),
          suffixIcon: suffix,
        ),
      );
}

class _Checkbox extends StatelessWidget {
  final bool value;
  final VoidCallback onTap;
  const _Checkbox({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
              color:
                  value ? AppColors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color:
                      value ? AppColors.blue : context.cBorder,
                  width: 1.5)),
          child: value
              ? const Icon(Icons.check_rounded,
                  size: 12, color: Colors.white)
              : null,
        ),
      );
}

class _GradientBtn extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _GradientBtn(
      {required this.label,
      required this.loading,
      required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF2E7D32)]),
              borderRadius: BorderRadius.circular(14)),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: loading ? null : onTap,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white)),
          ),
        ),
      );
}

class _GoogleBtn extends StatelessWidget {
  final BuildContext context;
  const _GoogleBtn({required this.context});

  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
            color: context.cCard,
            border: Border.all(color: context.cBorder),
            borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  shape: BoxShape.circle),
              child: const Center(
                  child: Text('G',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Text('Continuer avec Google',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.cText)),
        ]),
      );
}
