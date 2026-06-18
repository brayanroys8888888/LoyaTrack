from django.urls import path
from .views import (
    RegisterView, UserProfileView, UpdateFCMTokenView,
    LoginView, Login2FAVerifyView, Toggle2FAView,
    PasswordForgotView, PasswordVerifyOtpView, PasswordResetView,
    ChangePasswordView,
)

urlpatterns = [
    path('register/', RegisterView.as_view(), name='auth_register'),
    path('login/', LoginView.as_view(), name='auth_login'),
    path('login/verify-otp/', Login2FAVerifyView.as_view(), name='auth_login_verify_otp'),
    path('2fa/toggle/', Toggle2FAView.as_view(), name='auth_2fa_toggle'),
    path('change-password/', ChangePasswordView.as_view(), name='auth_change_password'),
    path('me/', UserProfileView.as_view(), name='auth_me'),
    path('fcm-token/', UpdateFCMTokenView.as_view(), name='auth_fcm_token'),
    # Réinitialisation de mot de passe par OTP SMS
    path('password/forgot/', PasswordForgotView.as_view(), name='auth_password_forgot'),
    path('password/verify-otp/', PasswordVerifyOtpView.as_view(), name='auth_password_verify_otp'),
    path('password/reset/', PasswordResetView.as_view(), name='auth_password_reset'),
]
