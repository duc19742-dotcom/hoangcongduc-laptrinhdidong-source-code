# Đức Attendance

Ứng dụng chấm công Flutter/Dart, ASP.NET Core .NET 10/EF Core 10, SQL Server. Project mobile bắt buộc `hoang_cong_duc`.

- `mobile/hoang_cong_duc`: ứng dụng Material 3 tiếng Việt, REST qua `http`, secure storage, camera QR, GPS và sensors_plus.
- `backend/Attendance.Api`: Controller/Repository/Service, JWT và role, Email OTP do Backend sinh; tích hợp Firebase SMS đang tắt và chờ cấu hình, CRUD, QR có hạn, chấm công idempotent, giải trình và audit.
- `tests/Attendance.Api.Tests`: test SQL Server LocalDB riêng; message transport chỉ capture trong test.
- `scripts`: cấu hình riêng, migration/deploy, build Android, chuẩn bị demo và kiểm tra public API.
- `.local`: bí mật, publish output, khóa ký và phiên thử; không đưa vào Git/gói nộp.

API đã triển khai: https://hoangcongduc-001-site1.itempurl.com

Swagger: `/swagger/index.html`. Kiểm tra database: `/api/v1/health/ready`. Màn hình trình chiếu QR: `/display.html`.

## Chạy Backend phát triển

```powershell
dotnet tool restore
dotnet restore DucAttendance.sln
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Initialize-Local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Configure-Services.ps1
cd backend\Attendance.Api
dotnet ef database update
dotnet run --launch-profile http
```

Cấu hình SMTP/SMS/Hosting/Admin được nhập tại máy trong `.local/secrets.json`. Không commit file này. Migration production dùng `scripts/Use-HostingDatabase.ps1`; bootstrap Admin chỉ dùng khi chưa có Admin.

## Chạy Mobile

Mở `mobile/hoang_cong_duc` bằng Android Studio. Chạy `flutter pub get`, `flutter devices`, `flutter run -d <ID điện thoại thật>`. API mặc định là HTTPS hosting; không đổi sang IP LAN/localhost để nộp bài.

Build release trên máy hiện tại: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-Android.ps1`. Máy khác truyền `-FlutterPath` và `-JavaHome` phù hợp; cần Android SDK và khóa ký riêng trước khi build release. Khóa ký hiện có ở `.local/attendance-release.jks` và Android `key.properties`, cần sao lưu riêng để cập nhật APK đã cài.

Gói source không kèm mật khẩu, khóa SMS/email, file publish production hoặc khóa ký Android. Muốn build release trên máy khác, tạo keystore của mình bằng `keytool -genkeypair`, rồi tạo `android/key.properties` theo mẫu. Không ghi đè keystore đang dùng.

## Kiểm thử

`dotnet test tests/Attendance.Api.Tests/Attendance.Api.Tests.csproj`; trong mobile chạy `flutter analyze` và `flutter test`.

Hiện có 33 test Backend và 11 test Flutter đạt; `flutter analyze` không có lỗi. Đã có bằng chứng thiết bị thật cho Email OTP, GPS/cảm biến, QR check-in/check-out, giải trình, quên mật khẩu và tải dữ liệu từ Wi-Fi khác mạng laptop.

Luồng đăng ký mới: nhân viên đăng ký và xác minh email → Admin mở Tài khoản chờ duyệt → chọn phòng ban → Duyệt nhân viên. Backend tự tạo hồ sơ từ dữ liệu đăng ký, sinh mã nếu để trống, liên kết và phê duyệt trong cùng transaction; không yêu cầu tạo nhân viên thêm lần nữa. Nếu đã có hồ sơ cùng email, Admin chọn liên kết hồ sơ đó.

SMS được để cuối theo yêu cầu người dùng, phương án đã thống nhất là Firebase quản lý OTP SMS và Backend kiểm tra ID token. Chưa cấu hình/bật và chưa có SMS thật thành công; không kết luận hoàn thành toàn bộ đồ án. Luồng duyệt đăng ký đã được kiểm thử tự động, cập nhật lên API/Android và người dùng xác nhận trên điện thoại: duyệt thành công, hồ sơ tự tạo.

Quy trình mới: QR chung theo địa điểm tự đổi + GPS mới + lịch định kỳ cá nhân/mặc định, có ưu tiên phân công riêng từng ngày. Ghi nhớ đăng nhập 30 ngày bằng mã thiết bị xoay vòng; không lưu mật khẩu. Hỗ trợ yêu cầu bổ sung lịch và Admin bổ sung giờ ra có audit, không giả GPS. Xem docs/QUY-TRINH-CHAM-CONG-MOI.md trong gói bàn giao.

