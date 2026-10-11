# xray-paas

Xray با VLESS + VMess + Trojan روی WebSocket، همه روی یک پورت، مناسب Render / Railway / Koyeb (Docker).

## متغیرهای محیطی
| نام | توضیح |
|---|---|
| `UUID` | **الزامی.** شناسه‌ی VLESS/VMess (و رمز Trojan، مگر `TROJAN_PASSWORD` بدهید) |
| `PUBLIC_HOST` | اختیاری. دامنه‌ی سرویس. Render و Railway خودشان تنظیمش می‌کنند |
| `XRAY_VERSION` | `latest` (پیش‌فرض) یا نسخه‌ی مشخص مثل `v25.1.1` |
| `UPDATE_INTERVAL_HOURS` | فاصله‌ی بررسی نسخه‌ی جدید (پیش‌فرض ۲۴) |
| `CONFIG_URL` | اختیاری. آدرس فایل JSON کامل Xray برای به‌روزرسانی خودکار کانفیگ. جانگهدارها: `__PORT__` و `__UUID__` |
| `PATH_PREFIX`, `SUB_TOKEN`, `NODE_NAME`, `TROJAN_PASSWORD` | اختیاری |

## لینک اشتراک
بعد از اجرا، در لاگ خط «لینک اشتراک» چاپ می‌شود: `https://دامنه/توکن`. آن را در کلاینت به‌عنوان Subscription وارد کنید.

## به‌روزرسانی
- در هر استارت، آخرین نسخه‌ی Xray از GitHub رسمی دانلود می‌شود (با بررسی SHA256 و تست اجرا و تست سازگاری با کانفیگ).
- هر `UPDATE_INTERVAL_HOURS` ساعت دوباره بررسی و در صورت وجود نسخه‌ی جدید، Xray خودکار ری‌استارت می‌شود.
- اگر `CONFIG_URL` تنظیم باشد، همان‌جا هم بررسی می‌شود و فقط کانفیگ معتبر اعمال می‌شود.

## کانفیگ‌های ساخته‌شده (۷ عدد)
| پروتکل | ترنسپورت |
|---|---|
| VLESS | WebSocket |
| VMess | WebSocket |
| Trojan | WebSocket |
| VLESS | HTTPUpgrade |
| VMess | HTTPUpgrade |
| Trojan | HTTPUpgrade |
| Shadowsocks (`chacha20-ietf-poly1305`) | WebSocket |

اگر Xray نصب‌شده کانفیگ کامل را نپذیرد، برنامه خودکار به حالت پایه (سه کانفیگ WebSocket) برمی‌گردد.
رمز Shadowsocks با متغیر `SS_PASSWORD` قابل تنظیم است (پیش‌فرض: همان `UUID`).
